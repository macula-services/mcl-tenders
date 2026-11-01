%%% @doc Today's intake of spotted tenders, and when the last notice arrived.
%%%
%%% T12: a flood of facts from a trusted sensor must not flood the dossiers.
%%% Each UTC day at most `MCL_TENDERS_DAILY_CAP' tenders are spotted (500 by
%%% default, far above a realm's normal share of TED's ~3,800 notices a
%%% day); the rest of the day's spots are dropped, counted, and the first drop
%%% is logged once, by count. get_tenders_page shows the counts, so the bid
%%% team sees the flag.
%%%
%%% T5: the time the last notice arrived, fitting or not, so a quiet stream
%%% shows on the morning list.
%%%
%%% Kept in memory: a restart starts the day's count again, which can admit at
%%% most one more cap's worth. Notice text never passes through here.
%%% @end
-module(tender_intake).
-behaviour(gen_server).

-export([start_link/0, admit/0, noted/0, today/0, cap/0]).
-export([init/1, handle_call/3, handle_cast/2, handle_info/2]).

-define(DEFAULT_CAP, 500).

-type today() :: #{day := binary(), spotted := non_neg_integer(), dropped := non_neg_integer(),
                   cap := pos_integer(), last_notice_at := non_neg_integer()}.
-export_type([today/0]).

-spec start_link() -> {ok, pid()} | {error, term()}.
start_link() ->
    gen_server:start_link({local, ?MODULE}, ?MODULE, [], []).

%% @doc `ok' to spot one more tender today, counting it; `capped' when the
%% day's cap is reached, counting the drop. A dead counter admits nothing.
-spec admit() -> ok | capped.
admit() ->
    called(admit, capped).

%% @doc A notice arrived, now.
-spec noted() -> ok.
noted() ->
    gen_server:cast(?MODULE, {noted, erlang:system_time(millisecond)}).

%% @doc Today's counts, the cap, and when the last notice arrived (0: none
%% since the node started).
-spec today() -> {ok, today()} | {error, unavailable}.
today() ->
    called(today, {error, unavailable}).

%% @doc The day's cap: `MCL_TENDERS_DAILY_CAP', a positive integer, or 500.
-spec cap() -> pos_integer().
cap() ->
    capped_at(string:to_integer(os:getenv("MCL_TENDERS_DAILY_CAP", ""))).

capped_at({N, []}) when is_integer(N), N > 0 -> N;
capped_at(_Unset) -> ?DEFAULT_CAP.

called(Request, Unavailable) ->
    try gen_server:call(?MODULE, Request, 5000)
    catch exit:_ -> Unavailable
    end.

init([]) ->
    {ok, #{day => day(), spotted => 0, dropped => 0, cap => cap(), last_notice_at => 0}}.

handle_call(admit, _From, St) ->
    counted(rolled(St));
handle_call(today, _From, St) ->
    #{day := {Y, M, D}} = Rolled = rolled(St),
    Day = iolist_to_binary(io_lib:format("~4..0b-~2..0b-~2..0b", [Y, M, D])),
    {reply, {ok, Rolled#{day := Day}}, Rolled};
handle_call(_Other, _From, St) ->
    {reply, {error, unknown_call}, St}.

handle_cast({noted, At}, St) -> {noreply, St#{last_notice_at := At}};
handle_cast(_Other, St) -> {noreply, St}.

handle_info(_Info, St) -> {noreply, St}.

counted(#{spotted := S, cap := Cap} = St) when S < Cap ->
    {reply, ok, St#{spotted := S + 1}};
counted(#{dropped := 0, cap := Cap} = St) ->
    logger:warning("[tenders] today's intake cap of ~b spotted tenders is reached; "
                   "the rest of today's are dropped and counted (MCL_TENDERS_DAILY_CAP)", [Cap]),
    {reply, capped, St#{dropped := 1}};
counted(#{dropped := D} = St) ->
    {reply, capped, St#{dropped := D + 1}}.

rolled(#{day := Day} = St) -> rolled(day(), Day, St).

rolled(Day, Day, St) -> St;
rolled(Today, _Yesterday, St) -> St#{day := Today, spotted := 0, dropped := 0}.

day() ->
    {Date, _Time} = calendar:universal_time(),
    Date.

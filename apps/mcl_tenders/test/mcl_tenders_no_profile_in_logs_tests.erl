%%% @doc T8: no profile term reaches a log or a crash report.
%%%
%%% The profile says what the realm bids for. It is on the node's disk, in the
%%% event store and the read model, and nowhere else: not in the logger, not
%%% in a crash report, not in an exit reason a supervisor reports. So every
%%% profile path runs here with canary terms, under a logger handler that keeps
%%% every event at every level, and each event is searched, all the way down,
%%% for a canary:
%%%
%%%   - the boot's initiation and a description that is stored;
%%%   - a description that is refused, carrying canaries;
%%%   - the profile read in process and through the responder;
%%%   - a description while the read-model store is stuck, so evoq's projection
%%%     fails and retries until the store answers again;
%%%   - a write that makes esqlite raise, carrying a canary;
%%%   - a notice that fits and one that does not, a correction, an award, a
%%%     tender dismissed, a spot the store refuses and a spot past the day's
%%%     cap, each carrying canaries in its codes-free text: which notices fit
%%%     draws the profile's outline (A2).
%%%
%%% Then format_status/1 of both stores, on a status shaped as a crash with a
%%% canary in the request and in the stack.
-module(mcl_tenders_no_profile_in_logs_tests).

-include_lib("eunit/include/eunit.hrl").

-export([log/2]).

-define(MEMBER, <<16#a1:256>>).
%% ASCII, so a match in any rendering of a binary or a string is a match.
-define(CANARIES, [<<"zqcpvkw0rd">>, <<"zqexcl0sion">>, <<"zqdescr1ption">>, <<"zqrefus3d">>,
                   <<"zqstuck">>, <<"zqraised">>, <<"zqn0tice">>, <<"zqbuy3r">>, <<"zqt1tle">>,
                   <<"zqm1ss">>]).

no_profile_in_logs_test_() ->
    {setup, fun start/0, fun stop/1,
     {timeout, 120, fun every_profile_path_leaves_no_canary_in_any_log/0}}.

start() ->
    Pipeline = mcl_tenders_pipeline:start("mcl_tenders_no_profile_in_logs_tests"),
    #{level := Level} = logger:get_primary_config(),
    ok = logger:set_primary_config(level, all),
    {Pipeline, Level}.

stop({Pipeline, Level}) ->
    ok = logger:set_primary_config(level, Level),
    mcl_tenders_pipeline:stop(Pipeline).

%% @doc The logger handler: every event to the test process, as it is.
log(Event, #{config := #{pid := Pid}}) ->
    Pid ! {logged, Event},
    ok.

%% The handler is added here, not in setup: eunit runs the test in a process
%% of its own, and the handler sends to the process that added it.
every_profile_path_leaves_no_canary_in_any_log() ->
    ok = logger:add_handler(?MODULE, ?MODULE, #{level => all, config => #{pid => self()}}),
    try every_profile_path_logged() after logger:remove_handler(?MODULE) end.

every_profile_path_logged() ->
    Realm = mcl_tenders_pipeline:realm(),
    ok = maybe_initiate_tender_profile:for_realm(Realm),
    {_, #{}} = describe(#{keywords => [{text, <<"zqcpvkw0rd">>}],
                          exclusions => [{text, <<"zqexcl0sion">>}],
                          description => {text, <<"zqdescr1ption">>}}),
    mcl_tenders_pipeline:eventually(fun() -> keywords(get_tender_profile:find(Realm)) end,
                                    [<<"zqcpvkw0rd">>]),
    %% Refused: a bidi override in a keyword, beside canaries.
    {_, #{<<"reason">> := _}} =
        describe(#{keywords => [{text, <<"zqrefus3d", 16#e2, 16#80, 16#ae>>}],
                   description => {text, <<"zqrefus3d">>}}),
    {_, #{<<"keywords">> := [{text, <<"zqcpvkw0rd">>}]}} =
        mcl_tenders_pipeline:call(<<"get_tender_profile">>, #{}, ?MEMBER),
    a_stuck_store_is_retried_without_a_canary_in_the_log(Realm),
    a_raise_in_the_store_is_answered_without_its_arguments(),
    every_dossier_path(Realm),
    Logged = drained([]),
    ?assertNotEqual([], Logged),
    ?assertEqual([], [{C, E} || E <- Logged, C <- ?CANARIES, carries(E, C)]).

%% The projection's write times out while the store is suspended, evoq retries,
%% and the description lands once the store answers again.
a_stuck_store_is_retried_without_a_canary_in_the_log(Realm) ->
    Store = whereis(tenders_read_model_store),
    ok = sys:suspend(Store),
    {_, #{}} = describe(#{keywords => [{text, <<"zqstuck">>}]}),
    timer:sleep(6_000),
    ok = sys:resume(Store),
    mcl_tenders_pipeline:eventually(fun() -> keywords(get_tender_profile:find(Realm)) end,
                                    [<<"zqstuck">>]).

a_raise_in_the_store_is_answered_without_its_arguments() ->
    Reply = tenders_read_model_store:exec("SELECT ?", [{<<"zqraised">>}]),
    ?assertMatch({error, {sqlite_raised, _, _}}, Reply),
    ?assertNot(carries(Reply, <<"zqraised">>)),
    ?assert(is_process_alive(whereis(tenders_read_model_store))).

every_dossier_path(Realm) ->
    {_, #{}} = describe(#{cpv_codes => [{text, <<"72000000">>}], countries => [{text, <<"NLD">>}],
                          keywords => [{text, <<"zqcpvkw0rd">>}]}),
    mcl_tenders_pipeline:eventually(fun() -> keywords(get_tender_profile:find(Realm)) end,
                                    [<<"zqcpvkw0rd">>]),
    Fact = fun(Overrides) ->
                   tender_notice_fixture:fact(
                     maps:merge(#{procedure_id => <<"canary-1">>, buyer_name => <<"zqbuy3r">>,
                                  titles => #{<<"eng">> => <<"zqt1tle">>},
                                  description => <<"zqn0tice zqcpvkw0rd">>}, Overrides))
           end,
    {spot_tender, ok} = mcl_tenders_pipeline:reported(Fact(#{})),
    {skipped, {no_fit, keyword}} =
        mcl_tenders_pipeline:reported(Fact(#{procedure_id => <<"canary-2">>,
                                             description => <<"zqm1ss zqn0tice">>})),
    {amend_tender, ok} = mcl_tenders_pipeline:reported(Fact(#{notice_type => <<"correction">>,
                                                              publication_number => <<"750001-2026">>})),
    {note_tender_award, ok} = mcl_tenders_pipeline:reported(Fact(#{notice_type => <<"award">>,
                                                                   publication_number => <<"760001-2026">>})),
    {_, #{}} = mcl_tenders_pipeline:call(<<"dismiss_tender">>, #{tender_id => {text, <<"canary-1">>}},
                                         ?MEMBER),
    mcl_tenders_pipeline:eventually(
      fun() -> maps:get(dismissed_by, element(2, get_tender_by_id:find(Realm, <<"canary-1">>))) end,
      binary:encode_hex(?MEMBER, lowercase)),
    Live = #{realm => fun mcl_om:realm/0, profile => fun get_tender_profile:find/1,
             noted => fun() -> ok end},
    {spot_tender, {error, store_error}} =
        on_tender_notice_reported_v1_maybe_spot_tender:handled(
          Fact(#{procedure_id => <<"canary-3">>}),
          Live#{admit => fun() -> ok end,
                dispatch => fun(_, Cmd) -> {error, {store_error, spot_tender_v1:to_map(Cmd)}} end}),
    {skipped, capped} =
        on_tender_notice_reported_v1_maybe_spot_tender:handled(
          Fact(#{procedure_id => <<"canary-4">>}),
          Live#{admit => fun() -> capped end, dispatch => fun(_, _) -> error(dispatched) end}),
    ok.

format_status_keeps_no_argument_test_() ->
    Status = #{state => kept, log => [{in, {exec, "SQL", [<<"zqfmt">>]}}],
               message => {exec, "INSERT ?", [<<"zqfmt">>]},
               reason => {badarg, [{esqlite3, q, [conn, "INSERT ?", [<<"zqfmt">>]], []}]}},
    [?_assertNot(carries(M:format_status(Status), <<"zqfmt">>))
     || M <- [tenders_read_model_store, tenders_query_store]] ++
    [?_assertMatch(#{message := {exec, "INSERT ?", redacted}, reason := {badarg, [{esqlite3, q, 3, []}]},
                     state := kept, log := []},
                   tenders_read_model_store:format_status(Status))].

%%--------------------------------------------------------------------

describe(Args) -> mcl_tenders_pipeline:call(<<"describe_tender_profile">>, Args, ?MEMBER).

keywords({ok, #{keywords := K}}) -> K;
keywords(Other) -> Other.

drained(Acc) ->
    receive {logged, E} -> drained([E | Acc])
    after 200 -> lists:reverse(Acc)
    end.

%% Whether Term carries Canary anywhere: in a binary, in a string, or in its
%% printed form (a report a formatter renders from a fun or a format string).
carries(Term, Canary) ->
    walked(Term, Canary) orelse
        binary:match(unicode:characters_to_binary(io_lib:format("~tp", [Term])), Canary) =/= nomatch.

walked(Bin, Canary) when is_binary(Bin) -> binary:match(Bin, Canary) =/= nomatch;
walked(List, Canary) when is_list(List) -> lists:any(fun(E) -> walked(E, Canary) end, improper(List));
walked(Tuple, Canary) when is_tuple(Tuple) -> walked(tuple_to_list(Tuple), Canary);
walked(Map, Canary) when is_map(Map) -> walked(maps:to_list(Map), Canary);
walked(_Other, _Canary) -> false.

improper([H | T]) when is_list(T) -> [H | improper(T)];
improper([H | T]) -> [H, T];
improper([]) -> [].

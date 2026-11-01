%%% @doc The TED sensor: sweep the notices published since the last sweep,
%%% report each new one as a `tender_notice_reported_v1' fact.
%%%
%%% On a heartbeat it asks TED's Search API (v3, anonymous, no key) for every
%%% notice published on or after its `since' day, in scroll mode: the first page
%%% answers a token, each later page is asked with the token the previous one
%%% gave, and TED keeps that snapshot until the next OJ S release plus 24 hours,
%%% so a sweep neither misses nor repeats a notice. Before a release appears the
%%% answer is empty, which costs one request.
%%%
%%% ONE SWEEP READS AT MOST A WEEK: the days from `since' to six days after it.
%%% A sensor far behind (a long lookback, a mesh dark for a month) catches up a
%%% week per sweep instead of asking for more than the page ceiling allows,
%%% which would end every sweep the same way and never move `since'. A week is
%%% some 27,000 notices: inside the page ceiling, and inside the reported window,
%%% so re-reading it after a failure never reports a notice twice.
%%%
%%% `since' moves only when EVERY notice of the sweep was reported. A dark mesh
%%% or a page TED refuses leaves it, so the next sweep reads the same days again
%%% and reports what is still missing; the notices that did go out sit in the
%%% reported window and are not sent twice. The first report that fails ends the
%%% sweep: with the mesh dark, the next one would fail the same way, and waiting
%%% out a timeout per notice of a 3,800-notice day helps nobody.
%%%
%%% Where it moves to: past the week, when the whole week lies before today, as
%%% those days are complete; otherwise to the newest day read, so that day is
%%% read once more and what TED had not yet indexed at this sweep is reported by
%%% the next (the window drops the rest). It holds no store: on a restart
%%% `since' starts again from today, and a day reported again is harmless,
%%% because company nodes deduplicate.
%%%
%%% IT ASKS FOR ALL OF TED, never for a company's codes or countries: the query
%%% names a date and nothing else, so TED learns nothing about who uses the
%%% notices (T3 of the design's threat model).
%%%
%%% POLITE TO TED. Pages are spaced, a scroll is cut off past a ceiling, and a
%%% failed sweep doubles the wait before the next one, up to six hours. TED's
%%% fair-usage page allows 700 requests a minute; it answered 429 to a handful
%%% of quick calls when it was read for this design, so the back-off is real.
-module(sense_ted_notices).
-behaviour(gen_server).

-export([start_link/0, sweep/4, delay/2, first_day/2, positive_int/2]).
-export([init/1, handle_call/3, handle_cast/2, handle_info/2, terminate/2]).

-define(SEARCH_URL, "https://api.ted.europa.eu/v3/notices/search").
-define(PAGE_SIZE, 250).            %% TED's maximum
-define(MAX_PAGES, 400).            %% 100,000 notices; a week has some 27,000
-define(SPAN_DAYS, 7).              %% the days one sweep reads
-define(PAGE_PAUSE_MS, 500).
-define(MAX_DELAY_MS, 21600000).    %% 6 hours
-define(DEFAULT_POLL_MS, 900000).   %% 15 minutes
-define(DEFAULT_MAX_SEEN, 30000).   %% about eight release days
-define(DEFAULT_LOOKBACK_DAYS, 0).
-define(FETCH_TIMEOUT, 30000).
-define(CONNECT_TIMEOUT, 10000).
-define(UA, "mcl-tenders-sensor/0.1 (+https://github.com/macula-services/mcl-tenders)").

-type day() :: calendar:date().
-type deps() :: #{search := fun((map()) -> {ok, map()} | {error, term()}),
                  report := fun((parse_ted_notice:notice()) -> ok | {error, term()}),
                  pause := fun(() -> ok)}.
-type stats() :: #{reported := non_neg_integer(), already_reported := non_neg_integer(),
                   skipped := non_neg_integer()}.

start_link() ->
    gen_server:start_link({local, ?MODULE}, ?MODULE, [], []).

init([]) ->
    _ = application:ensure_all_started(inets),
    _ = application:ensure_all_started(ssl),
    {Today, _Time} = calendar:universal_time(),
    PollMs = setting("MCL_TENDERS_POLL_MS", poll_ms, ?DEFAULT_POLL_MS),
    Since = first_day(Today, lookback_days()),
    logger:info("[tenders] sensor up: TED since ~ts, sweep every ~bs", [day(Since), PollMs div 1000]),
    self() ! sweep,
    {ok, #{since => Since, poll_ms => PollMs, failures => 0,
           window => reported_window:new(setting("MCL_TENDERS_MAX_SEEN", max_seen, ?DEFAULT_MAX_SEEN))}}.

handle_call(_Req, _From, St) -> {reply, {error, unknown_call}, St}.
handle_cast(_Msg, St)        -> {noreply, St}.

handle_info(sweep, #{since := Since, window := W} = St) ->
    {Today, _Time} = calendar:universal_time(),
    St2 = swept(sweep(Since, Today, W, live()), St),
    erlang:send_after(delay(maps:get(poll_ms, St2), maps:get(failures, St2)), self(), sweep),
    {noreply, St2};
handle_info(_Info, St) ->
    {noreply, St}.

terminate(_Reason, _St) -> ok.

swept({ok, Next, W, Stats}, #{since := Since} = St) ->
    logger:info("[tenders] swept TED since ~ts: ~b reported, ~b already reported, ~b not reported",
                [day(Since), maps:get(reported, Stats), maps:get(already_reported, Stats),
                 maps:get(skipped, Stats)]),
    St#{since := Next, window := W, failures := 0};
swept({error, Reason, W}, #{since := Since, failures := F} = St) ->
    logger:notice("[tenders] sweep of TED since ~ts stopped: ~0p", [day(Since), Reason]),
    St#{window := W, failures := F + 1}.

%%------------------------------------------------------------------------------
%% One sweep
%%------------------------------------------------------------------------------

%% @doc Read every notice published from `Since' to six days after it, and
%% report each one not in `Window'. Answers the day the next sweep starts from,
%% or why this one stopped; the window it answers holds every notice that did
%% go out.
-spec sweep(day(), day(), reported_window:window(), deps()) ->
          {ok, day(), reported_window:window(), stats()} |
          {error, term(), reported_window:window()}.
sweep(Since, Today, Window, Deps) ->
    Last = calendar:gregorian_days_to_date(calendar:date_to_gregorian_days(Since) + ?SPAN_DAYS - 1),
    Acc = #{since => Since, last => Last, today => Today, window => Window, newest => none,
            reported => 0, already_reported => 0, skipped => 0},
    page(request(Since, Last), 1, Acc, Deps).

request(Since, Last) ->
    #{<<"query">> => <<"publication-date>=", (day(Since))/binary,
                       " AND publication-date<=", (day(Last))/binary>>,
      <<"fields">> => parse_ted_notice:fields(),
      <<"limit">> => ?PAGE_SIZE,
      <<"scope">> => <<"ALL">>,
      <<"paginationMode">> => <<"ITERATION">>}.

page(_Body, N, #{window := W}, _Deps) when N > ?MAX_PAGES ->
    {error, too_many_pages, W};
page(Body, N, Acc, #{search := Search} = Deps) ->
    answered(Search(Body), Body, N, Acc, Deps).

answered({ok, #{<<"notices">> := []}}, _Body, _N, Acc, _Deps) ->
    finished(Acc);
answered({ok, #{<<"notices">> := Notices} = Reply}, Body, N, Acc, #{report := Report} = Deps)
  when is_list(Notices) ->
    ingested(ingest_all(Notices, Acc, Report), maps:get(<<"iterationNextToken">>, Reply, <<>>),
             Body, N, Deps);
answered({ok, Other}, _Body, _N, #{window := W}, _Deps) when is_map(Other) ->
    {error, {unexpected_answer, maps:keys(Other)}, W};
answered({ok, _NotAMap}, _Body, _N, #{window := W}, _Deps) ->
    {error, {unexpected_answer, not_an_object}, W};
answered({error, Reason}, _Body, _N, #{window := W}, _Deps) ->
    {error, Reason, W}.

%% No token: that was the last page.
next(Token, Body, N, Acc, #{pause := Pause} = Deps) when is_binary(Token), Token =/= <<>> ->
    ok = Pause(),
    page(Body#{<<"iterationNextToken">> => Token}, N + 1, Acc, Deps);
next(_NoToken, _Body, _N, Acc, _Deps) ->
    finished(Acc).

ingested({ok, Acc}, Token, Body, N, Deps) -> next(Token, Body, N, Acc, Deps);
ingested({error, _Reason, _W} = Stopped, _Token, _Body, _N, _Deps) -> Stopped.

finished(#{window := W} = Acc) ->
    {ok, next_since(Acc), W, maps:with([reported, already_reported, skipped], Acc)}.

%% A week wholly before today is complete: the next sweep starts after it.
%% Otherwise the newest day read is read again, as TED may still be adding to
%% it; an empty sweep leaves `since'.
next_since(#{last := Last, today := Today}) when Last < Today ->
    calendar:gregorian_days_to_date(calendar:date_to_gregorian_days(Last) + 1);
next_since(#{since := Since, newest := none}) -> Since;
next_since(#{since := Since, last := Last, newest := Newest}) ->
    Days = min(max(calendar:date_to_gregorian_days(Since), Newest), calendar:date_to_gregorian_days(Last)),
    calendar:gregorian_days_to_date(Days).

ingest_all([], Acc, _Report) -> {ok, Acc};
ingest_all([Json | Rest], Acc, Report) -> continued(ingest(Json, Acc, Report), Rest, Report).

continued({ok, Acc}, Rest, Report) -> ingest_all(Rest, Acc, Report);
continued({error, _Reason, _W} = Stopped, _Rest, _Report) -> Stopped.

ingest(Json, Acc, Report) when is_map(Json) ->
    parsed(parse_ted_notice:parse(Json), newest(parse_ted_notice:publication_day(Json), Acc), Report);
ingest(_NotAnObject, #{skipped := S} = Acc, _Report) ->
    {ok, Acc#{skipped := S + 1}}.

newest(none, Acc) -> Acc;
newest(Day, #{newest := none} = Acc) -> Acc#{newest := calendar:date_to_gregorian_days(Day)};
newest(Day, #{newest := N} = Acc) -> Acc#{newest := max(N, calendar:date_to_gregorian_days(Day))}.

parsed({skip, _Why}, #{skipped := S} = Acc, _Report) ->
    {ok, Acc#{skipped := S + 1}};
parsed({ok, #{publication_number := Number} = Notice}, #{window := W} = Acc, Report) ->
    reported(reported_window:seen(Number, W), Notice, Acc, Report).

reported(true, _Notice, #{already_reported := A} = Acc, _Report) ->
    {ok, Acc#{already_reported := A + 1}};
reported(false, Notice, Acc, Report) ->
    marked(Report(Notice), Notice, Acc).

marked(ok, #{publication_number := Number}, #{window := W, reported := R} = Acc) ->
    {ok, Acc#{window := reported_window:mark(Number, W), reported := R + 1}};
marked({error, Reason}, _Notice, #{window := W}) ->
    {error, {report_failed, Reason}, W}.

%%------------------------------------------------------------------------------
%% Pacing
%%------------------------------------------------------------------------------

%% @doc How long to wait before the next sweep after `Failures' failed ones in a
%% row: the poll interval, doubled per failure, never more than six hours.
-spec delay(pos_integer(), non_neg_integer()) -> pos_integer().
delay(PollMs, Failures) ->
    min(PollMs bsl min(Failures, 16), ?MAX_DELAY_MS).

%% @doc The first day a fresh sensor sweeps: today, less the configured lookback.
-spec first_day(day(), non_neg_integer()) -> day().
first_day(Today, LookbackDays) ->
    calendar:gregorian_days_to_date(calendar:date_to_gregorian_days(Today) - LookbackDays).

day({Y, M, D}) ->
    iolist_to_binary(io_lib:format("~4..0b~2..0b~2..0b", [Y, M, D])).

%%------------------------------------------------------------------------------
%% TED, over HTTPS
%%------------------------------------------------------------------------------

live() ->
    #{search => fun search/1,
      report => fun mcl_tenders_facts:report/1,
      pause => fun() -> timer:sleep(?PAGE_PAUSE_MS) end}.

search(Body) ->
    Request = {?SEARCH_URL, [{"User-Agent", ?UA}, {"Accept", "application/json"}],
               "application/json", iolist_to_binary(json:encode(Body))},
    HTTPOpts = [{timeout, ?FETCH_TIMEOUT}, {connect_timeout, ?CONNECT_TIMEOUT},
                {ssl, ssl_opts()}, {autoredirect, false}],
    reply(httpc:request(post, Request, HTTPOpts, [{body_format, binary}])).

reply({ok, {{_V, 200, _R}, _H, Body}}) -> decoded(Body);
reply({ok, {{_V, Code, _R}, _H, _B}})  -> {error, {http, Code}};
reply({error, Reason})                 -> {error, Reason}.

decoded(Body) ->
    try {ok, json:decode(Body)}
    catch error:_ -> {error, unreadable_answer}
    end.

%% TED's certificate is verified against the system trust store, with pure OTP:
%% inets and ssl, no SDK. A bad chain fails the sweep, which then backs off;
%% that is the right outcome for an answer that cannot be shown to be TED's.
ssl_opts() ->
    [{verify, verify_peer},
     {cacerts, public_key:cacerts_get()},
     {depth, 5},
     {customize_hostname_check,
      [{match_fun, public_key:pkix_verify_hostname_match_fun(https)}]}].

%%------------------------------------------------------------------------------
%% Config
%%------------------------------------------------------------------------------

lookback_days() ->
    non_negative(string:to_integer(os:getenv("MCL_TENDERS_LOOKBACK_DAYS", "")),
                 application:get_env(sense_tender_notices, lookback_days, ?DEFAULT_LOOKBACK_DAYS)).

non_negative({I, _Rest}, _Fallback) when is_integer(I), I >= 0 -> I;
non_negative(_NotACount, Fallback) -> Fallback.

setting(EnvVar, Key, Default) ->
    positive_int(os:getenv(EnvVar), application:get_env(sense_tender_notices, Key, Default)).

%% @doc The integer in `Value', or `Fallback' when it is unset, not an integer,
%% or not positive: a zero poll interval is a hot loop against TED, and a zero
%% window reports everything on every sweep.
-spec positive_int(string() | false, pos_integer()) -> pos_integer().
positive_int(false, Fallback) ->
    Fallback;
positive_int(Value, Fallback) ->
    positive(string:to_integer(Value), Fallback).

positive({I, _Rest}, _Fallback) when is_integer(I), I > 0 -> I;
positive(_NotPositive, Fallback) -> Fallback.

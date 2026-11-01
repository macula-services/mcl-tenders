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
%%% those days are complete. Otherwise to the newest day read, AS LONG AS that
%%% sweep reported something new of that day: the next sweep reads it again, and
%%% what TED had not yet indexed is reported then (the window drops the rest).
%%% A sweep that finds nothing new of its newest day moves past it. So a release
%%% day costs two reads in the steady state, whether `since' sat on that day
%%% before its release or behind it, not one per sweep until the next release:
%%% every realm runs a sensor, and TED pays for each of them. It holds no store: on a restart
%%% `since' starts again from today, and a day reported again is harmless,
%%% because company nodes deduplicate.
%%%
%%% IT ASKS FOR THE REALM'S CPV CODES AND COUNTRIES, and nothing else of the
%%% profile (T3 of the threat model, as amended: Raf's decision, owner the
%%% realm). Each sweep reads the profile in process (get_tender_profile:find/1),
%%% and the query names the days, the codes and the countries: never a keyword,
%%% an exclusion or the description. TED's CPV match is hierarchical, so
%%% `72000000' brings `72315000' too, and a country is the buyer's
%%% (`buyer-country'). The codes are checked as codes again before they reach
%%% the query, whatever the read model holds (T6).
%%%
%%% IT STAYS IDLE, ASKING TED NOTHING, while the realm has no profile with at
%%% least one code and one country, or while the node cannot seal what it would
%%% report (tender_notices_group:missing/0): the facts are the realm's matches,
%%% and never travel in the clear. Idle, `since' is held at today less the
%%% lookback, so a profile set later is read from then and not from the day the
%%% node first booted. The reason is logged once each time it changes, naming
%%% variables, never values.
%%%
%%% POLITE TO TED. Pages are spaced, a scroll is cut off past a ceiling, and a
%%% failed sweep doubles the wait before the next one, up to six hours. TED's
%%% fair-usage page allows 700 requests a minute; it answered 429 to a handful
%%% of quick calls when it was read for this design, so the back-off is real.
-module(sense_ted_notices).
-behaviour(gen_server).

-export([start_link/0, sweep/4, interest_in/1, delay/2, first_day/2, positive_int/2]).
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
-define(UA, "mcl-tenders/0.1 (+https://github.com/macula-services/mcl-tenders)").
-define(CPV, "^[0-9]{8}\\z").
-define(COUNTRY, "^[A-Z]{3}\\z").

-type day() :: calendar:date().
-type interest() :: {ok, [binary()], [binary()]} | {idle, term()}.
-type deps() :: #{interest := fun(() -> interest()),
                  search := fun((map()) -> {ok, map()} | {error, term()}),
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
    Lookback = lookback_days(),
    Since = first_day(Today, Lookback),
    logger:info("[tenders] sensor up: TED since ~ts, sweep every ~bs", [day(Since), PollMs div 1000]),
    self() ! sweep,
    {ok, #{since => Since, poll_ms => PollMs, failures => 0, lookback => Lookback, idle => none,
           window => reported_window:new(setting("MCL_TENDERS_MAX_SEEN", max_seen, ?DEFAULT_MAX_SEEN))}}.

handle_call(_Req, _From, St) -> {reply, {error, unknown_call}, St}.
handle_cast(_Msg, St)        -> {noreply, St}.

handle_info(sweep, #{since := Since, window := W} = St) ->
    {Today, _Time} = calendar:universal_time(),
    St2 = swept(sweep(Since, Today, W, live()), Today, St),
    erlang:send_after(delay(maps:get(poll_ms, St2), maps:get(failures, St2)), self(), sweep),
    {noreply, St2};
handle_info(_Info, St) ->
    {noreply, St}.

terminate(_Reason, _St) -> ok.

swept({idle, Why, W}, Today, #{lookback := Lookback, idle := Was} = St) ->
    ok = idle_noted(Why, Was),
    St#{since := first_day(Today, Lookback), window := W, failures := 0, idle := Why};
swept(Swept, _Today, St) ->
    swept(Swept, St#{idle := none}).

idle_noted(Same, Same) -> ok;
idle_noted(Why, _Was) -> logger:notice("[tenders] sensor idle, TED not asked: ~0p", [Why]).

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

%% @doc Read every notice in the realm's CPV codes and countries published from
%% `Since' to six days after it, and report each one not in `Window'. Answers
%% the day the next sweep starts from, why this one stopped, or why it did not
%% ask TED at all; the window it answers holds every notice that did go out.
-spec sweep(day(), day(), reported_window:window(), deps()) ->
          {ok, day(), reported_window:window(), stats()} |
          {error, term(), reported_window:window()} |
          {idle, term(), reported_window:window()}.
sweep(Since, Today, Window, #{interest := Interest} = Deps) ->
    interested(Interest(), Since, Today, Window, Deps).

interested({idle, Why}, _Since, _Today, Window, _Deps) ->
    {idle, Why, Window};
interested({ok, Cpv, Countries}, Since, Today, Window, Deps) ->
    Last = calendar:gregorian_days_to_date(calendar:date_to_gregorian_days(Since) + ?SPAN_DAYS - 1),
    Acc = #{since => Since, last => Last, today => Today, window => Window, newest => none,
            fresh => none,
            reported => 0, already_reported => 0, skipped => 0},
    page(request(Since, Last, Cpv, Countries), 1, Acc, Deps).

request(Since, Last, Cpv, Countries) ->
    #{<<"query">> => <<"publication-date>=", (day(Since))/binary,
                       " AND publication-date<=", (day(Last))/binary,
                       " AND classification-cpv IN (", (spaced(Cpv))/binary, ")",
                       " AND buyer-country IN (", (spaced(Countries))/binary, ")">>,
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
%% Otherwise the newest day is read again while a sweep still reports something
%% new of it, as TED may still be adding to it; a sweep that reported nothing
%% new of its newest day was that second read, and the next sweep starts after
%% it, whether or not `since' already sat on that day. An empty sweep leaves
%% `since'.
next_since(#{last := Last, today := Today}) when Last < Today ->
    calendar:gregorian_days_to_date(calendar:date_to_gregorian_days(Last) + 1);
next_since(#{since := Since, newest := none}) -> Since;
next_since(#{newest := Newest, fresh := Newest}) -> calendar:gregorian_days_to_date(Newest);
next_since(#{newest := Newest}) -> calendar:gregorian_days_to_date(Newest + 1).

ingest_all([], Acc, _Report) -> {ok, Acc};
ingest_all([Json | Rest], Acc, Report) -> continued(ingest(Json, Acc, Report), Rest, Report).

continued({ok, Acc}, Rest, Report) -> ingest_all(Rest, Acc, Report);
continued({error, _Reason, _W} = Stopped, _Rest, _Report) -> Stopped.

ingest(Json, #{last := Last} = Acc, Report) when is_map(Json) ->
    Day = within(gregorian(parse_ted_notice:publication_day(Json)), calendar:date_to_gregorian_days(Last)),
    parsed(parse_ted_notice:parse(Json), Day, latest(newest, Day, Acc), Report);
ingest(_NotAnObject, #{skipped := S} = Acc, _Report) ->
    {ok, Acc#{skipped := S + 1}}.

gregorian(none) -> none;
gregorian(Day) -> calendar:date_to_gregorian_days(Day).

%% A notice dated past the week asked for counts as its last day, so it never
%% moves `since' beyond the week.
within(none, _Last) -> none;
within(Day, Last) -> min(Day, Last).

%% The newest day read (`newest'), or the newest day of a notice reported new
%% in this sweep (`fresh').
latest(_Key, none, Acc) -> Acc;
latest(Key, Day, Acc) -> later(maps:get(Key, Acc), Key, Day, Acc).

later(none, Key, Day, Acc) -> Acc#{Key := Day};
later(Was, Key, Day, Acc) -> Acc#{Key := max(Was, Day)}.

parsed({skip, _Why}, _Day, #{skipped := S} = Acc, _Report) ->
    {ok, Acc#{skipped := S + 1}};
parsed({ok, #{publication_number := Number} = Notice}, Day, #{window := W} = Acc, Report) ->
    reported(reported_window:seen(Number, W), Notice, Day, Acc, Report).

reported(true, _Notice, _Day, #{already_reported := A} = Acc, _Report) ->
    {ok, Acc#{already_reported := A + 1}};
reported(false, Notice, Day, Acc, Report) ->
    marked(Report(Notice), Notice, Day, Acc).

marked(ok, #{publication_number := Number}, Day, #{window := W, reported := R} = Acc) ->
    {ok, latest(fresh, Day, Acc#{window := reported_window:mark(Number, W), reported := R + 1})};
marked({error, Reason}, _Notice, _Day, #{window := W}) ->
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

spaced(Codes) -> iolist_to_binary(lists:join(<<" ">>, Codes)).

%%------------------------------------------------------------------------------
%% What the realm is interested in
%%------------------------------------------------------------------------------

%% @doc The interest a profile read answers: its CPV codes and countries, each
%% checked as a code again (anything else is dropped, T6), or why the sensor
%% stays idle. A profile needs at least one code and one country: a query
%% without either would ask TED for all of a kind, which is not what the realm
%% described.
-spec interest_in({ok, map()} | {error, term()}) -> interest().
interest_in({ok, #{cpv_codes := Cpv, countries := Countries}}) ->
    narrowed(codes(Cpv, ?CPV), codes(Countries, ?COUNTRY));
interest_in({error, not_found}) ->
    {idle, no_profile};
interest_in({error, archived}) ->
    {idle, archived};
interest_in({error, Reason}) ->
    {idle, {profile_unreadable, Reason}}.

narrowed([], _Countries) -> {idle, no_profile};
narrowed(_Cpv, []) -> {idle, no_profile};
narrowed(Cpv, Countries) -> {ok, Cpv, Countries}.

codes(List, Pattern) when is_list(List) ->
    lists:usort([C || C <- List, is_binary(C), re:run(C, Pattern, [{capture, none}]) =:= match]);
codes(_NotAList, _Pattern) ->
    [].

%% Live: the node must be able to seal before TED is asked anything, and then
%% the realm's own profile, read in process.
interest() ->
    ready(tender_notices_group:missing()).

ready([]) -> realm_interest(mcl_om:realm());
ready(Missing) -> {idle, {sealing_unset, Missing}}.

realm_interest({ok, <<_:256>> = Realm}) -> interest_in(get_tender_profile:find(Realm));
realm_interest(_NoRealm) -> {idle, no_realm}.

day({Y, M, D}) ->
    iolist_to_binary(io_lib:format("~4..0b~2..0b~2..0b", [Y, M, D])).

%%------------------------------------------------------------------------------
%% TED, over HTTPS
%%------------------------------------------------------------------------------

live() ->
    #{interest => fun interest/0,
      search => fun search/1,
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

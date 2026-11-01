%%% @doc One sweep of TED, without network or mesh: the search and the report
%%% are injected, so every test sees exactly what was asked and what would have
%%% been reported.
%%%
%%% A sweep reads every notice in the realm's CPV codes and countries published
%%% in the week from its `since' day, page by page in TED's scroll mode, and
%%% reports each one not reported before.
%%% `since' moves only when every notice of the sweep was reported, so a dark
%%% mesh or a refused page delays a notice and loses none.
-module(sense_ted_notices_tests).

-include_lib("eunit/include/eunit.hrl").

-define(SINCE, {2026, 10, 28}).
-define(TODAY, {2026, 10, 30}).

notice(Number, Date) ->
    ted_notice_fixture:notice(#{<<"publication-number">> => Number,
                                <<"publication-date">> => <<Date/binary, "+01:00">>}).

%% TED's answer, as pages: each page names the token of the next one, and the
%% page after the last is empty.
pages(Pages) ->
    Self = self(),
    Numbered = lists:zip(lists:seq(1, length(Pages)), Pages),
    fun(Body) ->
            Self ! {searched, Body},
            Page = page_number(maps:get(<<"iterationNextToken">>, Body, undefined)),
            {ok, page(proplists:get_value(Page, Numbered, []), Page)}
    end.

page(Notices, N) ->
    #{<<"notices">> => Notices, <<"totalNoticeCount">> => 99,
      <<"iterationNextToken">> => <<"token-", (integer_to_binary(N + 1))/binary>>}.

page_number(undefined) -> 1;
page_number(<<"token-", N/binary>>) -> binary_to_integer(N).

reporting(Result) ->
    Self = self(),
    fun(#{publication_number := Number}) -> Self ! {reported, Number}, Result end.

-define(CPV, [<<"48000000">>, <<"72000000">>]).
-define(COUNTRIES, [<<"BEL">>, <<"NLD">>]).

deps(Search, Report) -> deps(fun() -> {ok, ?CPV, ?COUNTRIES} end, Search, Report).

deps(Interest, Search, Report) ->
    #{interest => Interest, search => Search, report => Report, pause => fun() -> ok end}.

window() -> reported_window:new(1000).

sweep(Search, Report) -> sweep(Search, Report, window()).
%% Tests share one process: what an earlier sweep sent is drained first.
sweep(Search, Report, Window) ->
    sweep(?SINCE, Search, Report, Window).
sweep(Since, Search, Report, Window) ->
    _ = {reported(), searched()},
    sense_ted_notices:sweep(Since, ?TODAY, Window, deps(Search, Report)).

reported() -> drain(reported, []).
searched() -> drain(searched, []).

drain(Tag, Acc) ->
    receive {Tag, X} -> drain(Tag, [X | Acc]) after 0 -> lists:reverse(Acc) end.

%% T3: the query names the week it reads, the realm's CPV codes and its
%% countries, and nothing else of the profile; scroll mode, the closed field
%% list. These are the only things TED learns from this realm.
the_query_names_the_week_the_codes_and_the_countries_only_test() ->
    _ = sweep(pages([]), reporting(ok)),
    [Body] = searched(),
    ?assertEqual(<<"publication-date>=20261028 AND publication-date<=20261103"
                   " AND classification-cpv IN (48000000 72000000)"
                   " AND buyer-country IN (BEL NLD)">>,
                 maps:get(<<"query">>, Body)),
    ?assertEqual(lists:sort([<<"query">>, <<"fields">>, <<"limit">>, <<"scope">>,
                             <<"paginationMode">>]),
                 lists:sort(maps:keys(Body))),
    ?assertEqual(<<"ITERATION">>, maps:get(<<"paginationMode">>, Body)),
    ?assertEqual(<<"ALL">>, maps:get(<<"scope">>, Body)),
    ?assertEqual(250, maps:get(<<"limit">>, Body)),
    ?assertEqual(parse_ted_notice:fields(), maps:get(<<"fields">>, Body)),
    ?assertNot(maps:is_key(<<"iterationNextToken">>, Body)).

%% Every page is read, each with the token the previous one gave, until TED
%% answers an empty page.
every_page_is_read_test() ->
    P1 = [notice(<<"1-2026">>, <<"2026-10-28">>), notice(<<"2-2026">>, <<"2026-10-28">>)],
    P2 = [notice(<<"3-2026">>, <<"2026-10-29">>)],
    {ok, _Next, _W, _Stats} = sweep(pages([P1, P2]), reporting(ok)),
    ?assertEqual([<<"1-2026">>, <<"2-2026">>, <<"3-2026">>], reported()),
    Tokens = [maps:get(<<"iterationNextToken">>, B, none) || B <- searched()],
    ?assertEqual([none, <<"token-2">>, <<"token-3">>], Tokens).

%% A complete sweep that reaches today moves since to the newest day it read,
%% so that day is read once more: what TED had not indexed yet at this sweep is
%% reported by the next, and what it had is already in the window.
a_complete_sweep_moves_since_to_the_newest_day_test() ->
    P1 = [notice(<<"1-2026">>, <<"2026-10-29">>), notice(<<"2-2026">>, <<"2026-10-28">>)],
    ?assertMatch({ok, {2026, 10, 29}, _, _}, sweep(pages([P1]), reporting(ok))).

%% T15: the second read reports only what is new, and then since moves past that
%% day: a release day is read twice, not once per sweep until the next release,
%% because every realm runs a sensor and TED pays for each of them.
the_newest_day_is_read_once_more_and_then_left_test() ->
    P1 = [notice(<<"1-2026">>, <<"2026-10-29">>)],
    {ok, Next, W, _} = sweep(pages([P1]), reporting(ok)),
    ?assertEqual({2026, 10, 29}, Next),
    ?assertMatch({ok, {2026, 10, 30}, _, #{reported := 0, already_reported := 1}},
                 sweep(Next, pages([P1]), reporting(ok), W)).

%% TED still adding to the newest day at the second read: what it added is
%% reported, and the day is read again until a read finds nothing new of it.
a_day_still_growing_is_read_until_nothing_new_test() ->
    P1 = [notice(<<"1-2026">>, <<"2026-10-29">>)],
    {ok, Next, W, _} = sweep(pages([P1]), reporting(ok)),
    _ = reported(),
    P2 = [notice(<<"1-2026">>, <<"2026-10-29">>), notice(<<"2-2026">>, <<"2026-10-29">>)],
    {ok, Next2, W2, Stats} = sweep(Next, pages([P2]), reporting(ok), W),
    ?assertEqual({{2026, 10, 29}, #{reported => 1, already_reported => 1, skipped => 0}},
                 {Next2, Stats}),
    ?assertEqual([<<"2-2026">>], reported()),
    ?assertMatch({ok, {2026, 10, 30}, _, #{reported := 0}}, sweep(Next2, pages([P2]), reporting(ok), W2)).

%% THE STEADY STATE (Pluto, PR #7 r1): `since' already sits on the day being
%% released, as it does after every quiet sweep. Its release is read twice all
%% the same: the first read finds it new and stays, the second finds nothing
%% new and moves on. What TED indexed between the two reads is not lost.
the_release_of_the_day_since_sits_on_is_read_twice_test() ->
    Day = {2026, 10, 30},
    ?assertMatch({ok, Day, _, #{reported := 0}}, sweep(Day, pages([]), reporting(ok), window())),
    P1 = [notice(<<"1-2026">>, <<"2026-10-30">>)],
    {ok, Next, W, _} = sweep(Day, pages([P1]), reporting(ok), window()),
    ?assertEqual({Day, [<<"1-2026">>]}, {Next, reported()}),
    P2 = [notice(<<"1-2026">>, <<"2026-10-30">>), notice(<<"2-2026">>, <<"2026-10-30">>)],
    {ok, Next2, W2, _} = sweep(Next, pages([P2]), reporting(ok), W),
    ?assertEqual({Day, [<<"2-2026">>]}, {Next2, reported()}),
    ?assertMatch({ok, {2026, 10, 31}, _, #{reported := 0, already_reported := 2}},
                 sweep(Next2, pages([P2]), reporting(ok), W2)).

%% A sensor far behind (a long lookback, a mesh dark for weeks) reads one week
%% per sweep and moves past it, so it catches up rather than asking for more
%% than the page ceiling and failing the same way forever.
a_sensor_far_behind_catches_up_a_week_per_sweep_test() ->
    Since = {2026, 8, 31},
    P1 = [notice(<<"1-2026">>, <<"2026-09-02">>)],
    ?assertMatch({ok, {2026, 9, 7}, _, #{reported := 1}},
                 sweep(Since, pages([P1]), reporting(ok), window())),
    [Body | _] = searched(),
    ?assertMatch({match, _}, re:run(maps:get(<<"query">>, Body),
                                    <<"^publication-date>=20260831 AND publication-date<=20260906 AND ">>)),
    ?assertMatch({ok, {2026, 9, 7}, _, #{reported := 0}},
                 sweep(Since, pages([]), reporting(ok), window())).

%% A notice dated outside the week asked for never moves since beyond it.
a_notice_outside_the_week_does_not_move_since_beyond_it_test() ->
    P1 = [notice(<<"1-2026">>, <<"2026-12-25">>)],
    ?assertMatch({ok, {2026, 11, 3}, _, _}, sweep(pages([P1]), reporting(ok))).

%% An empty answer (no release yet today) leaves since where it is.
an_empty_sweep_leaves_since_test() ->
    ?assertMatch({ok, ?SINCE, _, #{reported := 0}}, sweep(pages([]), reporting(ok))).

%% A notice already reported is not reported again.
a_reported_notice_is_not_reported_again_test() ->
    W = reported_window:mark(<<"1-2026">>, window()),
    P1 = [notice(<<"1-2026">>, <<"2026-10-28">>), notice(<<"2-2026">>, <<"2026-10-28">>)],
    {ok, _, _, Stats} = sweep(pages([P1]), reporting(ok), W),
    ?assertEqual([<<"2-2026">>], reported()),
    ?assertMatch(#{reported := 1, already_reported := 1}, Stats).

%% A report that fails (dark mesh, refused publish) ends the sweep there and
%% leaves since: the next notice would fail the same way, one timeout each. The
%% next sweep reads the same days and reports the rest; the notices that did go
%% out are not sent twice.
a_failed_report_ends_the_sweep_and_is_retried_by_the_next_test() ->
    P1 = [notice(<<"1-2026">>, <<"2026-10-28">>), notice(<<"2-2026">>, <<"2026-10-28">>),
          notice(<<"3-2026">>, <<"2026-10-28">>)],
    Self = self(),
    Flaky = fun(#{publication_number := <<"2-2026">>}) -> {error, mesh_unavailable};
               (#{publication_number := N}) -> Self ! {reported, N}, ok
            end,
    ?assertMatch({error, {report_failed, mesh_unavailable}, _}, sweep(pages([P1]), Flaky)),
    {error, _, W} = sweep(pages([P1]), Flaky),
    ?assertEqual([<<"1-2026">>], reported()),
    {ok, Next, W2, Stats} = sweep(pages([P1]), reporting(ok), W),
    ?assertEqual({?SINCE, #{reported => 2, already_reported => 1, skipped => 0}}, {Next, Stats}),
    ?assertEqual([<<"2-2026">>, <<"3-2026">>], reported()),
    %% It found new notices of its newest day, so that day is read once more.
    ?assertMatch({ok, {2026, 10, 29}, _, #{reported := 0}}, sweep(pages([P1]), reporting(ok), W2)).

%% A page TED refuses ends the sweep: since stays, and the window keeps what
%% was reported before the refusal.
a_refused_page_ends_the_sweep_test() ->
    P1 = [notice(<<"1-2026">>, <<"2026-10-28">>)],
    Search = fun(#{<<"iterationNextToken">> := _}) -> {error, {http, 429}};
                (Body) -> (pages([P1]))(Body)
             end,
    {error, {http, 429}, W} = sweep(Search, reporting(ok)),
    ?assert(reported_window:seen(<<"1-2026">>, W)).

%% A notice that is not reported (another form, a malformed number) is counted
%% and does not hold since back: it would be skipped again on every sweep.
a_skipped_notice_is_counted_and_does_not_hold_since_test() ->
    P1 = [notice(<<"1-2026">>, <<"2026-10-29">>),
          ted_notice_fixture:notice(#{<<"form-type">> => <<"cont-modif">>}),
          ted_notice_fixture:notice(#{<<"publication-number">> => <<"bad">>})],
    {ok, Next, _, Stats} = sweep(pages([P1]), reporting(ok)),
    ?assertEqual({2026, 10, 29}, Next),
    ?assertMatch(#{reported := 1, skipped := 2}, Stats).

%% An answer that is not the shape TED documents ends the sweep rather than
%% being taken as "no more notices".
an_unexpected_answer_ends_the_sweep_test() ->
    ?assertMatch({error, {unexpected_answer, _}, _},
                 sweep(fun(_) -> {ok, #{<<"message">> => <<"busy">>}} end, reporting(ok))).

%% A scroll that never ends is cut off: the sensor never reads without bound.
an_endless_scroll_is_cut_off_test() ->
    Endless = fun(_) -> {ok, page([notice(<<"1-2026">>, <<"2026-10-28">>)], 1)} end,
    ?assertMatch({error, too_many_pages, _}, sweep(Endless, reporting(ok))).

%%------------------------------------------------------------------------------
%% The realm's interest
%%------------------------------------------------------------------------------

%% No profile with a code and a country, or no way to seal: TED is not asked.
an_idle_sensor_asks_ted_nothing_test_() ->
    [?_assertMatch({idle, Why, _}, idle_sweep(Why))
     || Why <- [no_profile, {sealing_unset, ["MCL_TENDERS_GROUP_UCAN"]}, no_realm]].

idle_sweep(Why) ->
    _ = searched(),
    Search = fun(Body) -> self() ! {searched, Body}, {ok, page([], 1)} end,
    Result = sense_ted_notices:sweep(?SINCE, ?TODAY, window(),
                                     deps(fun() -> {idle, Why} end, Search, reporting(ok))),
    [] = searched(),
    Result.

%% The profile read answers the codes and countries, each checked as a code
%% again whatever the read model holds (T6), so nothing but a code reaches the
%% query; and a profile without a code or a country leaves the sensor idle.
the_interest_is_the_profile_codes_and_countries_test() ->
    Profile = fun(Cpv, Countries) ->
                      {ok, #{cpv_codes => Cpv, countries => Countries, keywords => [<<"secret">>],
                             exclusions => [<<"also secret">>], description => <<"nope">>}}
              end,
    ?assertEqual({ok, [<<"72000000">>], [<<"BEL">>]},
                 sense_ted_notices:interest_in(Profile([<<"72000000">>, <<"72000000">>,
                                                        <<"72000000) OR (x">>, 7],
                                                       [<<"BEL">>, <<"be">>, <<"BEL OR">>]))),
    ?assertEqual({idle, no_profile}, sense_ted_notices:interest_in(Profile([], [<<"BEL">>]))),
    ?assertEqual({idle, no_profile}, sense_ted_notices:interest_in(Profile([<<"72000000">>], []))),
    ?assertEqual({idle, no_profile}, sense_ted_notices:interest_in({error, not_found})),
    ?assertEqual({idle, {profile_unreadable, store_unavailable}},
                 sense_ted_notices:interest_in({error, store_unavailable})).

%%------------------------------------------------------------------------------
%% Pacing
%%------------------------------------------------------------------------------

%% After a failure the next sweep waits longer, doubling up to a ceiling, and
%% one success puts it back. TED answered 429 to a handful of quick calls when
%% it was read for this design, so backing off is not hypothetical.
a_failing_sensor_backs_off_test() ->
    Poll = 900000,
    ?assertEqual([900000, 1800000, 3600000, 7200000, 14400000, 21600000, 21600000],
                 [sense_ted_notices:delay(Poll, F) || F <- lists:seq(0, 6)]).

the_first_day_is_today_less_the_lookback_test() ->
    ?assertEqual({2026, 11, 1}, sense_ted_notices:first_day({2026, 11, 1}, 0)),
    ?assertEqual({2026, 10, 30}, sense_ted_notices:first_day({2026, 11, 1}, 2)).

%% A zero poll interval is a hot loop against TED, and a zero window reports
%% everything on every sweep: both fall back to the default.
a_zero_or_invalid_setting_falls_back_to_the_default_test() ->
    ?assertEqual(900000, sense_ted_notices:positive_int("0", 900000)),
    ?assertEqual(900000, sense_ted_notices:positive_int("-5", 900000)),
    ?assertEqual(900000, sense_ted_notices:positive_int("soon", 900000)),
    ?assertEqual(900000, sense_ted_notices:positive_int(false, 900000)),
    ?assertEqual(60000, sense_ted_notices:positive_int("60000", 900000)).

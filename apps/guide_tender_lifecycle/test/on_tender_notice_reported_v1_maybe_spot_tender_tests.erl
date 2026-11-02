%%% @doc The process manager's whole decision, handled/2, with its
%%% dependencies given: no mesh, no store.
-module(on_tender_notice_reported_v1_maybe_spot_tender_tests).

-include_lib("eunit/include/eunit.hrl").

-import(tender_notice_fixture, [fact/0, fact/1, profile/0, profile/1, realm/0]).

-define(PM, on_tender_notice_reported_v1_maybe_spot_tender).

%% Dependencies that record what was dispatched in the test process's mailbox.
deps() -> deps(#{}).

deps(Overrides) ->
    Self = self(),
    maps:merge(#{realm => fun() -> {ok, realm()} end,
                 profile => fun(_Realm) -> {ok, profile()} end,
                 admit => fun() -> ok end,
                 spotted => fun() -> Self ! spotted, ok end,
                 noted => fun() -> Self ! noted, ok end,
                 dispatch => fun(Desk, Cmd) -> Self ! {dispatched, Desk, Cmd}, {ok, 1, []} end},
               Overrides).

dispatched() ->
    receive {dispatched, Desk, Cmd} -> {Desk, Cmd} after 0 -> none end.

drain() ->
    receive _ -> drain() after 0 -> ok end.

a_fitting_contract_notice_is_spotted_test() ->
    ?assertEqual({spot_tender, ok}, ?PM:handled(fact(), deps())),
    {spot_tender, Cmd} = dispatched(),
    ?assertMatch(#{realm := _, tender_id := <<"85e562c1-17d1-4192-a543-082edb9b62ab">>,
                   matched_cpv_codes := [<<"72000000">>], matched_keywords := []},
                 spot_tender_v1:to_map(Cmd)),
    drain().

a_prior_information_notice_is_spotted_too_test() ->
    ?assertEqual({spot_tender, ok},
                 ?PM:handled(fact(#{notice_type => <<"prior_information">>}), deps())),
    drain().

a_notice_that_does_not_fit_leaves_nothing_test() ->
    ?assertEqual({skipped, {no_fit, keyword}},
                 ?PM:handled(fact(), deps(#{profile => fun(_) -> {ok, profile(#{keywords => [<<"cobol">>]})} end}))),
    ?assertEqual(none, dispatched()),
    drain().

a_correction_goes_to_amend_tender_test() ->
    ?assertEqual({amend_tender, ok}, ?PM:handled(fact(#{notice_type => <<"correction">>}), deps())),
    ?assertMatch({amend_tender, _}, dispatched()),
    drain().

an_award_goes_to_note_tender_award_test() ->
    ?assertEqual({note_tender_award, ok}, ?PM:handled(fact(#{notice_type => <<"award">>}), deps())),
    ?assertMatch({note_tender_award, _}, dispatched()),
    drain().

%% A correction or award does not need the profile: it only touches a
%% dossier that exists.
a_correction_does_not_read_the_profile_test() ->
    NoProfile = deps(#{profile => fun(_) -> error(profile_read) end}),
    ?assertEqual({amend_tender, ok}, ?PM:handled(fact(#{notice_type => <<"correction">>}), NoProfile)),
    drain().

the_expected_refusals_are_answers_not_faults_test() ->
    [?assertEqual({spot_tender, Why},
                  ?PM:handled(fact(), deps(#{dispatch => fun(_, _) -> {error, Why} end})))
     || Why <- [already_spotted, not_spotted, already_noted]],
    ?assertEqual({spot_tender, {error, store_error}},
                 ?PM:handled(fact(), deps(#{dispatch => fun(_, _) -> {error, {store_error, x}} end}))),
    drain().

past_the_days_cap_nothing_is_spotted_test() ->
    ?assertEqual({skipped, capped}, ?PM:handled(fact(), deps(#{admit => fun() -> capped end}))),
    ?assertEqual(none, dispatched()),
    drain().

%% Only a stored spot takes a place under the day's cap: a notice the
%% aggregate refuses as already spotted (a restarted sensor re-reports its
%% window), or a failed store, takes none; a stored one takes exactly one.
only_a_stored_spot_takes_a_place_under_the_cap_test() ->
    drain(),
    ?assertEqual({spot_tender, already_spotted},
                 ?PM:handled(fact(), deps(#{dispatch => fun(_, _) -> {error, already_spotted} end}))),
    receive spotted -> ?assert(false) after 0 -> ok end,
    ?assertEqual({spot_tender, {error, store_error}},
                 ?PM:handled(fact(), deps(#{dispatch => fun(_, _) -> {error, {store_error, x}} end}))),
    receive spotted -> ?assert(false) after 0 -> ok end,
    ?assertEqual({spot_tender, ok}, ?PM:handled(fact(), deps())),
    receive spotted -> ok after 0 -> ?assert(false) end,
    receive spotted -> ?assert(false) after 0 -> ok end,
    drain().

%% The cap counts spots only: a notice that does not fit is not admitted.
a_notice_that_does_not_fit_takes_no_place_under_the_cap_test() ->
    Self = self(),
    Counting = deps(#{admit => fun() -> Self ! admitted, ok end,
                      profile => fun(_) -> {ok, profile(#{countries => [<<"BEL">>]})} end}),
    ?assertEqual({skipped, {no_fit, country}}, ?PM:handled(fact(), Counting)),
    receive admitted -> ?assert(false) after 0 -> ok end,
    drain().

every_fact_is_noted_even_a_dropped_one_test() ->
    ?assertEqual({skipped, publication_number},
                 ?PM:handled(fact(#{publication_number => <<"nope">>}), deps())),
    receive noted -> ok after 0 -> ?assert(false) end,
    drain().

no_realm_or_no_profile_spots_nothing_test() ->
    ?assertEqual({skipped, no_realm}, ?PM:handled(fact(), deps(#{realm => fun() -> {error, x} end}))),
    ?assertEqual({skipped, no_profile},
                 ?PM:handled(fact(), deps(#{profile => fun(_) -> {error, not_found} end}))),
    ?assertEqual(none, dispatched()),
    drain().

the_subscriber_callbacks_keep_their_state_test() ->
    D = deps(#{dispatch => fun(_, _) -> {ok, 1, []} end}),
    ?assertEqual({noreply, D}, ?PM:handle_event(<<"t">>, fact(), #{}, D)),
    ?assertEqual({noreply, D}, ?PM:handle_unopened(<<"t">>, #{publisher => <<1:256>>, reason => r}, D)),
    drain().

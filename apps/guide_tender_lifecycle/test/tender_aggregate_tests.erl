%%% @doc A tender dossier's lifecycle rules, through the three callbacks evoq
%%% drives (init/1, execute/2, apply/2): no store, no mesh, no process.
-module(tender_aggregate_tests).

-include_lib("eunit/include/eunit.hrl").
-include("../src/tender_status.hrl").

-import(tender_notice_fixture, [notice/0, notice/1, realm/0, member/0]).

spot() ->
    {ok, Cmd} = spot_tender_v1:new(#{realm => realm(), notice => notice(),
                                     reasons => #{matched_cpv_codes => [<<"72000000">>],
                                                  matched_keywords => [<<"erlang">>]}}),
    spot_tender_v1:to_map(Cmd).

amend() ->
    {ok, Cmd} = amend_tender_v1:new(#{realm => realm(),
                                      notice => notice(#{notice_type => <<"correction">>,
                                                         publication_number => <<"750001-2026">>,
                                                         deadline_at => 1796000000000})}),
    amend_tender_v1:to_map(Cmd).

award() ->
    {ok, Cmd} = note_tender_award_v1:new(#{realm => realm(),
                                           notice => notice(#{notice_type => <<"award">>,
                                                              publication_number => <<"760001-2026">>})}),
    note_tender_award_v1:to_map(Cmd).

dismiss() ->
    {ok, Cmd} = dismiss_tender_v1:new(#{realm => realm(), dismissed_by => member(),
                                        tender_id => tender_notice:tender_id(notice())}),
    dismiss_tender_v1:to_map(Cmd).

fresh() ->
    {ok, S} = tender_aggregate:init(<<"tender-00">>),
    S.

step(State, Cmd) ->
    folded(tender_aggregate:execute(State, Cmd), State).

folded({ok, Events}, State) ->
    {ok, lists:foldl(fun(E, S) -> tender_aggregate:apply(S, E) end, State, Events)};
folded({error, _} = E, _State) ->
    E.

steps(Cmds) ->
    lists:foldl(fun(C, {ok, S}) -> step(S, C) end, {ok, fresh()}, Cmds).

spotting_records_the_notice_flat_with_its_reasons_test() ->
    {ok, [Ev]} = tender_aggregate:execute(fresh(), spot()),
    ?assertMatch(#{event_type := <<"tender_spotted_v1">>, realm := _,
                   tender_id := <<"85e562c1-17d1-4192-a543-082edb9b62ab">>,
                   publication_number := <<"745687-2026">>, buyer_country := <<"NLD">>,
                   matched_cpv_codes := [<<"72000000">>], matched_keywords := [<<"erlang">>],
                   spotted_at := At} when is_integer(At), Ev),
    ?assertNot(maps:is_key(notice, Ev)),
    {ok, S} = step(fresh(), spot()),
    ?assertEqual(?TENDER_SPOTTED, tender_state:status(S)).

a_tender_is_spotted_once_test() ->
    ?assertEqual({error, already_spotted}, steps([spot(), spot()])).

nothing_but_spotting_acts_on_a_tender_never_spotted_test() ->
    [?assertEqual({error, not_spotted}, step(fresh(), Cmd)) || Cmd <- [amend(), award(), dismiss()]].

a_correction_carries_only_the_correctable_fields_test() ->
    {ok, S} = steps([spot()]),
    {ok, [Ev]} = tender_aggregate:execute(S, amend()),
    ?assertEqual(lists:sort([event_type, realm, tender_id, amended_at | amend_tender_v1:fields()]),
                 lists:sort(maps:keys(Ev))),
    ?assertMatch(#{deadline_at := 1796000000000, publication_number := <<"750001-2026">>}, Ev).

corrections_come_as_often_as_the_buyer_publishes_them_test() ->
    {ok, S} = steps([spot(), amend(), amend()]),
    ?assertEqual(?TENDER_SPOTTED bor ?TENDER_AMENDED, tender_state:status(S)).

the_award_is_noted_once_test() ->
    {ok, S} = steps([spot(), award()]),
    ?assertEqual(?TENDER_SPOTTED bor ?TENDER_AWARD_PUBLISHED, tender_state:status(S)),
    ?assertEqual({error, already_noted}, step(S, award())).

a_tender_is_dismissed_once_by_its_caller_test() ->
    {ok, S} = steps([spot()]),
    {ok, [Ev]} = tender_aggregate:execute(S, dismiss()),
    ?assertMatch(#{event_type := <<"tender_dismissed_v1">>, dismissed_by := _}, Ev),
    ?assertEqual(member(), maps:get(dismissed_by, Ev)),
    {ok, S2} = step(S, dismiss()),
    ?assertEqual({error, already_dismissed}, step(S2, dismiss())).

a_dismissal_names_a_caller_and_a_valid_id_test() ->
    ?assertEqual({error, no_caller},
                 dismiss_tender_v1:new(#{realm => realm(), tender_id => <<"745687-2026">>})),
    ?assertEqual({error, invalid_tender_id},
                 dismiss_tender_v1:new(#{realm => realm(), dismissed_by => member(),
                                         tender_id => <<"x/y">>})).

an_unknown_command_is_refused_test() ->
    ?assertEqual({error, unknown_command}, tender_aggregate:execute(fresh(), #{command_type => bid})),
    ?assertEqual({error, unknown_command}, tender_aggregate:execute(fresh(), #{})).

%% T8 / A2: the state evoq keeps, and puts in a crash report, holds flags only.
the_state_holds_no_notice_text_test() ->
    {ok, S} = steps([spot(), amend()]),
    ?assertEqual([status, stream], lists:sort(maps:keys(tender_state:to_map(S)))).

the_stream_is_one_per_realm_and_tender_test() ->
    A = tender_aggregate:stream_id(realm(), <<"745687-2026">>),
    ?assertMatch({match, _}, re:run(A, "^[a-z]{1,32}-[a-f0-9]{32}$")),
    ?assertNotEqual(A, tender_aggregate:stream_id(realm(), <<"745688-2026">>)),
    ?assertNotEqual(A, tender_aggregate:stream_id(<<16#5f:256>>, <<"745687-2026">>)).

the_flags_are_powers_of_two_test() ->
    ?assertEqual([1, 2, 4, 8], [?TENDER_SPOTTED, ?TENDER_AMENDED, ?TENDER_AWARD_PUBLISHED,
                                ?TENDER_DISMISSED]).

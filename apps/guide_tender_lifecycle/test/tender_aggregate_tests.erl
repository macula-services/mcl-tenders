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

%% A pursuit desk's command, by the role holder member().
pursuit(Module, ByKey) -> pursuit(Module, ByKey, #{}).

pursuit(Module, ByKey, Extra) ->
    {ok, Cmd} = Module:new(maps:merge(#{realm => realm(), ByKey => member(),
                                        tender_id => tender_notice:tender_id(notice())}, Extra)),
    Module:to_map(Cmd).

pursue() -> pursuit(pursue_tender_v1, pursued_by).
decline() -> pursuit(decline_tender_v1, declined_by).
submit() -> pursuit(submit_tender_bid_v1, submitted_by).
outcome(Outcome) -> pursuit(record_tender_outcome_v1, recorded_by, #{outcome => Outcome}).

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
    [?assertEqual({error, not_spotted}, step(fresh(), Cmd)) || Cmd <- [amend(), award(), dismiss(), pursue(), decline(), submit(),
                                                         outcome(<<"won">>)]].

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
    ?assertEqual([1, 2, 4, 8, 16, 32, 64, 128, 256],
                 [?TENDER_SPOTTED, ?TENDER_AMENDED, ?TENDER_AWARD_PUBLISHED, ?TENDER_DISMISSED,
                  ?TENDER_PURSUED, ?TENDER_DECLINED, ?TENDER_BID_SUBMITTED, ?TENDER_WON,
                  ?TENDER_LOST]).

%%--------------------------------------------------------------------
%% The pursuit (#4b)
%%--------------------------------------------------------------------

%% Bid: pursue, put the bid in, learn the outcome. Each event names the caller
%% the command carried, the node macula verified (T13).
a_pursuit_runs_from_bid_to_won_test() ->
    {ok, S} = steps([spot(), pursue(), submit()]),
    {ok, [Ev]} = tender_aggregate:execute(S, outcome(<<"won">>)),
    ?assertMatch(#{event_type := <<"tender_outcome_recorded_v1">>, outcome := <<"won">>,
                   recorded_at := At} when is_integer(At), Ev),
    ?assertEqual(member(), maps:get(recorded_by, Ev)),
    {ok, S2} = step(S, outcome(<<"won">>)),
    ?assertEqual(?TENDER_SPOTTED bor ?TENDER_PURSUED bor ?TENDER_BID_SUBMITTED bor ?TENDER_WON,
                 tender_state:status(S2)),
    ?assertEqual({error, already_recorded}, step(S2, outcome(<<"lost">>))),
    ?assertEqual({error, already_submitted}, step(S2, decline())).

a_lost_bid_is_recorded_as_lost_test() ->
    {ok, S} = steps([spot(), pursue(), submit(), outcome(<<"lost">>)]),
    ?assertEqual(?TENDER_LOST, tender_state:status(S) band (?TENDER_WON bor ?TENDER_LOST)),
    ?assertEqual({error, already_recorded}, step(S, outcome(<<"won">>))).

each_pursuit_event_names_its_caller_test() ->
    {ok, S0} = steps([spot()]),
    {ok, [Pursued]} = tender_aggregate:execute(S0, pursue()),
    ?assertMatch(#{event_type := <<"tender_pursued_v1">>, pursued_by := _, pursued_at := _}, Pursued),
    {ok, S1} = step(S0, pursue()),
    {ok, [Submitted]} = tender_aggregate:execute(S1, submit()),
    ?assertMatch(#{event_type := <<"tender_bid_submitted_v1">>, submitted_at := _}, Submitted),
    {ok, [Declined]} = tender_aggregate:execute(S1, decline()),
    ?assertMatch(#{event_type := <<"tender_declined_v1">>, declined_at := _}, Declined),
    [?assertEqual(member(), maps:get(K, E))
     || {K, E} <- [{pursued_by, Pursued}, {submitted_by, Submitted}, {declined_by, Declined}]].

%% No bid: pursued, then declined; nothing more moves it.
a_declined_pursuit_takes_no_bid_test() ->
    {ok, S} = steps([spot(), pursue(), decline()]),
    ?assertEqual(?TENDER_SPOTTED bor ?TENDER_PURSUED bor ?TENDER_DECLINED, tender_state:status(S)),
    ?assertEqual({error, declined}, step(S, submit())),
    ?assertEqual({error, already_declined}, step(S, decline())),
    ?assertEqual({error, not_submitted}, step(S, outcome(<<"won">>))).

each_pursuit_step_waits_for_the_one_before_test() ->
    {ok, Spotted} = steps([spot()]),
    ?assertEqual({error, not_pursued}, step(Spotted, decline())),
    ?assertEqual({error, not_pursued}, step(Spotted, submit())),
    ?assertEqual({error, not_submitted}, step(Spotted, outcome(<<"won">>))),
    {ok, Pursued} = step(Spotted, pursue()),
    ?assertEqual({error, already_pursued}, step(Pursued, pursue())),
    ?assertEqual({error, not_submitted}, step(Pursued, outcome(<<"won">>))).

%% "Not for us" comes before a pursuit; a pursued tender is declined instead.
dismissing_and_pursuing_exclude_each_other_test() ->
    ?assertEqual({error, dismissed}, steps([spot(), dismiss(), pursue()])),
    ?assertEqual({error, pursued}, steps([spot(), pursue(), dismiss()])).

%% Corrections and the award keep reaching a pursued dossier.
a_pursued_tender_still_takes_its_corrections_and_award_test() ->
    {ok, S} = steps([spot(), pursue(), submit(), amend(), award()]),
    ?assertEqual(?TENDER_SPOTTED bor ?TENDER_PURSUED bor ?TENDER_BID_SUBMITTED bor ?TENDER_AMENDED
                     bor ?TENDER_AWARD_PUBLISHED, tender_state:status(S)).

a_pursuit_command_names_a_caller_a_valid_id_and_an_outcome_test() ->
    Id = tender_notice:tender_id(notice()),
    [?assertEqual({error, no_caller}, M:new(#{realm => realm(), tender_id => Id, outcome => <<"won">>}))
     || M <- [pursue_tender_v1, decline_tender_v1, submit_tender_bid_v1, record_tender_outcome_v1]],
    [?assertEqual({error, invalid_tender_id},
                  M:new(#{realm => realm(), By => member(), tender_id => <<"x/y">>, outcome => <<"won">>}))
     || {M, By} <- [{pursue_tender_v1, pursued_by}, {decline_tender_v1, declined_by},
                    {submit_tender_bid_v1, submitted_by}, {record_tender_outcome_v1, recorded_by}]],
    [?assertEqual({error, invalid_outcome},
                  record_tender_outcome_v1:new(#{realm => realm(), recorded_by => member(),
                                                 tender_id => Id, outcome => Bad}))
     || Bad <- [<<"WON">>, <<"draw">>, <<>>, undefined, won]].

%% The pursuit's papers (#25): a document or a question, by the role holder.
document(Sha) ->
    pursuit(attach_tender_document_v1, attached_by,
            #{name => <<"offer.pdf">>, sha256 => Sha, location => <<"bids/offer.pdf">>}).

question(Text) -> pursuit(record_tender_question_v1, recorded_by, #{question => Text}).

-define(SHA, <<"0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef">>).

papers_come_only_with_a_pursuit_test() ->
    ?assertEqual({error, not_spotted}, steps([document(?SHA)])),
    ?assertEqual({error, not_spotted}, steps([question(<<"Q?">>)])),
    ?assertEqual({error, not_pursued}, steps([spot(), document(?SHA)])),
    ?assertEqual({error, not_pursued}, steps([spot(), question(<<"Q?">>)])).

%% As often as the bid team needs, whatever the pursuit has come to, and
%% without a flag of their own.
papers_come_as_often_as_needed_test() ->
    {ok, S} = steps([spot(), pursue(), document(?SHA), question(<<"Q?">>), submit(),
                     document(?SHA), question(<<"Q2?">>), outcome(<<"lost">>), question(<<"Q3?">>)]),
    ?assertEqual(?TENDER_SPOTTED bor ?TENDER_PURSUED bor ?TENDER_BID_SUBMITTED bor ?TENDER_LOST,
                 tender_state:status(S)),
    {ok, Declined} = steps([spot(), pursue(), decline()]),
    ?assertMatch({ok, _}, step(Declined, document(?SHA))).

each_paper_event_names_its_caller_and_keeps_no_more_test() ->
    {ok, Pursued} = steps([spot(), pursue()]),
    {ok, [Doc]} = tender_aggregate:execute(Pursued, document(?SHA)),
    ?assertMatch(#{event_type := <<"tender_document_attached_v1">>, name := <<"offer.pdf">>,
                   sha256 := ?SHA, location := <<"bids/offer.pdf">>, attached_at := _}, Doc),
    ?assertEqual(member(), maps:get(attached_by, Doc)),
    {ok, [Q]} = tender_aggregate:execute(Pursued, question(<<"Q?">>)),
    ?assertMatch(#{event_type := <<"tender_question_recorded_v1">>, question := <<"Q?">>}, Q),
    ?assertEqual(member(), maps:get(recorded_by, Q)),
    ?assertEqual(binary:encode_hex(crypto:hash(sha256, <<"Q?">>), lowercase), maps:get(question_id, Q)).

a_document_names_a_caller_a_valid_id_a_name_a_digest_and_a_place_test() ->
    Id = tender_notice:tender_id(notice()),
    Good = #{realm => realm(), attached_by => member(), tender_id => Id, name => <<"offer.pdf">>,
             sha256 => ?SHA, location => <<"bids/offer.pdf">>},
    ?assertMatch({ok, _}, attach_tender_document_v1:new(Good)),
    [?assertEqual({error, Why}, attach_tender_document_v1:new(maps:merge(Good, Bad)))
     || {Why, Bad} <- [{no_caller, #{attached_by => undefined}},
                       {invalid_tender_id, #{tender_id => <<"x/y">>}},
                       {invalid_document_name, #{name => <<>>}},
                       {invalid_document_name, #{name => binary:copy(<<"a">>, 256)}},
                       {invalid_document_name, #{name => <<"offer", 16#e2, 16#80, 16#ae, ".pdf">>}},
                       {invalid_document_name, #{name => <<"a\nb">>}},
                       {invalid_sha256, #{sha256 => string:uppercase(?SHA)}},
                       {invalid_sha256, #{sha256 => binary:part(?SHA, 0, 63)}},
                       {invalid_sha256, #{sha256 => <<?SHA/binary, "\n">>}},
                       {invalid_sha256, #{sha256 => undefined}},
                       {invalid_location, #{location => <<>>}},
                       {invalid_location, #{location => binary:copy(<<"a">>, 1025)}},
                       {invalid_location, #{location => <<"a", 0, "b">>}}]],
    ?assertEqual({error, invalid_realm}, attach_tender_document_v1:new(maps:remove(realm, Good))).

a_question_names_a_caller_a_valid_id_and_its_text_test() ->
    Id = tender_notice:tender_id(notice()),
    Good = #{realm => realm(), recorded_by => member(), tender_id => Id,
             question => <<"Line one\nline two">>},
    ?assertMatch({ok, _}, record_tender_question_v1:new(Good)),
    [?assertEqual({error, Why}, record_tender_question_v1:new(maps:merge(Good, Bad)))
     || {Why, Bad} <- [{no_caller, #{recorded_by => <<1, 2>>}},
                       {invalid_tender_id, #{tender_id => <<>>}},
                       {invalid_question, #{question => <<>>}},
                       {invalid_question, #{question => binary:copy(<<"a">>, 4001)}},
                       {invalid_question, #{question => <<"zero", 16#e2, 16#80, 16#8b, "width">>}},
                       {invalid_question, #{question => <<"tab\there">>}},
                       {invalid_question, #{question => 42}}]].

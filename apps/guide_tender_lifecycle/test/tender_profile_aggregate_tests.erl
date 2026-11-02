%%% @doc The tender profile's lifecycle rules, through the three callbacks evoq
%%% drives (init/1, execute/2, apply/2): no store, no mesh, no process.
-module(tender_profile_aggregate_tests).

-include_lib("eunit/include/eunit.hrl").

%% Synthetic ids: this repository is public.
-define(REALM, <<16#5e:256>>).
-define(MEMBER, <<16#a1:256>>).

initiate() -> #{command_type => initiate_tender_profile_v1, realm => ?REALM}.

describe_unless_described() ->
    {ok, Cmd} = describe_tender_profile_v1:new(#{realm => ?REALM, described_by => ?MEMBER,
                                                 cpv_codes => [<<"72000000">>],
                                                 countries => [<<"BEL">>],
                                                 unless_described => 1}),
    describe_tender_profile_v1:to_map(Cmd).

describe() ->
    {ok, Cmd} = describe_tender_profile_v1:new(#{realm => ?REALM, described_by => ?MEMBER,
                                                 cpv_codes => [<<"72000000">>],
                                                 countries => [<<"BEL">>]}),
    describe_tender_profile_v1:to_map(Cmd).

archive() ->
    {ok, Cmd} = archive_tender_profile_v1:new(#{realm => ?REALM, archived_by => ?MEMBER}),
    archive_tender_profile_v1:to_map(Cmd).

fresh() ->
    {ok, S} = tender_profile_aggregate:init(?REALM),
    S.

%% Executes one command and folds what it produced, as evoq does.
step(State, Cmd) ->
    folded(tender_profile_aggregate:execute(State, Cmd), State).

folded({ok, Events}, State) ->
    {ok, lists:foldl(fun(E, S) -> tender_profile_aggregate:apply(S, E) end, State, Events)};
folded({error, _} = E, _State) ->
    E.

initiating_the_profile_records_it_test() ->
    {ok, [Ev]} = tender_profile_aggregate:execute(fresh(), initiate()),
    ?assertMatch(#{event_type := <<"tender_profile_initiated_v1">>, realm := ?REALM,
                   initiated_at := At} when is_integer(At), Ev),
    {ok, S} = step(fresh(), initiate()),
    ?assertEqual(1, tender_profile_state:status(S)).

the_profile_is_initiated_once_test() ->
    {ok, S} = step(fresh(), initiate()),
    ?assertEqual({error, already_initiated}, step(S, initiate())).

a_profile_not_initiated_cannot_be_described_test() ->
    ?assertEqual({error, not_initiated}, step(fresh(), describe())).

describing_an_initiated_profile_records_every_field_test() ->
    {ok, S} = step(fresh(), initiate()),
    {ok, [Ev]} = tender_profile_aggregate:execute(S, describe()),
    ?assertMatch(#{event_type := <<"tender_profile_described_v1">>, realm := ?REALM,
                   described_by := ?MEMBER, cpv_codes := [<<"72000000">>],
                   countries := [<<"BEL">>], keywords := [], exclusions := [],
                   description := <<>>, described_at := At} when is_integer(At), Ev),
    {ok, S2} = step(S, describe()),
    ?assertEqual(1 bor 2, tender_profile_state:status(S2)),
    %% Described again, as often as the realm likes: each replaces the last.
    ?assertMatch({ok, _}, step(S2, describe())).

%% `unless_described' (the node's config, at boot): it describes a profile
%% never described, and is refused on one described already, so the realm's
%% own description is kept. Without it, describing again replaces as before.
describing_unless_described_applies_only_to_an_undescribed_profile_test() ->
    {ok, S} = step(fresh(), initiate()),
    {ok, S2} = step(S, describe_unless_described()),
    ?assertEqual(1 bor 2, tender_profile_state:status(S2)),
    ?assertEqual({error, already_described}, step(S2, describe_unless_described())),
    ?assertMatch({ok, _}, step(S2, describe())),
    {ok, S3} = step(S, describe()),
    ?assertEqual({error, already_described}, step(S3, describe_unless_described())),
    ?assertEqual({error, not_initiated}, step(fresh(), describe_unless_described())).

%% T8: the state evoq keeps in memory, and puts in a crash report, carries no
%% profile term. The rules need only the flags.
the_state_holds_no_profile_term_test() ->
    {ok, S1} = step(fresh(), initiate()),
    {ok, S2} = step(S1, describe()),
    ?assertEqual(#{realm => ?REALM, status => 3}, tender_profile_state:to_map(S2)).

a_profile_not_initiated_cannot_be_archived_test() ->
    ?assertEqual({error, not_initiated}, step(fresh(), archive())).

archiving_the_profile_records_who_and_when_test() ->
    {ok, S} = step(fresh(), initiate()),
    {ok, [Ev]} = tender_profile_aggregate:execute(S, archive()),
    ?assertMatch(#{event_type := <<"tender_profile_archived_v1">>, realm := ?REALM,
                   archived_by := ?MEMBER, archived_at := At} when is_integer(At), Ev),
    {ok, S2} = step(S, archive()),
    ?assertEqual(1 bor 4, tender_profile_state:status(S2)).

%% Archived is the end of the profile's life: nothing more is recorded on it.
an_archived_profile_is_neither_archived_again_nor_described_test() ->
    {ok, S1} = step(fresh(), initiate()),
    {ok, S2} = step(S1, describe()),
    {ok, S3} = step(S2, archive()),
    ?assertEqual(1 bor 2 bor 4, tender_profile_state:status(S3)),
    ?assertEqual({error, already_archived}, step(S3, archive())),
    ?assertEqual({error, archived}, step(S3, describe())),
    %% A boot after the archive still finds the profile there, as it wants.
    ?assertEqual({error, already_initiated}, step(S3, initiate())).

an_unknown_command_is_refused_test() ->
    ?assertEqual({error, unknown_command},
                 step(fresh(), #{command_type => publish_tender_profile_v1})),
    ?assertEqual({error, unknown_command}, step(fresh(), #{})).

a_command_without_its_realm_is_refused_test() ->
    ?assertEqual({error, invalid_realm},
                 step(fresh(), #{command_type => initiate_tender_profile_v1})),
    ?assertEqual({error, invalid_realm},
                 step(fresh(), #{command_type => initiate_tender_profile_v1, realm => <<1:248>>})).

%% reckon-db stream ids must match ^[a-z]{1,32}-[a-f0-9]{32}$.
the_stream_id_is_one_reckon_db_accepts_test() ->
    Id = tender_profile_aggregate:stream_id(?REALM),
    ?assertMatch({match, _}, re:run(Id, "^[a-z]{1,32}-[a-f0-9]{32}$")),
    ?assertNotEqual(Id, tender_profile_aggregate:stream_id(<<16#5f:256>>)).

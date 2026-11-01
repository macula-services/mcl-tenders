%%% @doc Who may be named as archiving the realm's profile: the caller's node
%%% id, 32 bytes, and the realm id, 32 bytes. Nothing else is in the command.
-module(archive_tender_profile_v1_tests).

-include_lib("eunit/include/eunit.hrl").

-define(REALM, <<16#5e:256>>).
-define(MEMBER, <<16#a1:256>>).

an_archive_names_the_realm_and_the_caller_test() ->
    {ok, Cmd} = archive_tender_profile_v1:new(#{realm => ?REALM, archived_by => ?MEMBER}),
    ?assertEqual(#{command_type => archive_tender_profile_v1, realm => ?REALM,
                   archived_by => ?MEMBER}, archive_tender_profile_v1:to_map(Cmd)),
    ?assertEqual(tender_profile_aggregate:stream_id(?REALM),
                 archive_tender_profile_v1:stream_id(Cmd)).

an_archive_without_a_caller_is_refused_test_() ->
    [?_assertEqual({error, no_caller}, archive_tender_profile_v1:new(Params))
     || Params <- [#{realm => ?REALM}, #{realm => ?REALM, archived_by => undefined},
                   #{realm => ?REALM, archived_by => <<1:248>>}]].

an_archive_without_a_realm_id_is_refused_test_() ->
    [?_assertEqual({error, invalid_realm}, archive_tender_profile_v1:new(Params))
     || Params <- [#{archived_by => ?MEMBER}, #{realm => <<"io.example">>, archived_by => ?MEMBER}]].

%% evoq hands the command back as a map: what new/1 built rebuilds the same.
the_map_evoq_hands_back_rebuilds_the_command_test() ->
    {ok, Cmd} = archive_tender_profile_v1:new(#{realm => ?REALM, archived_by => ?MEMBER}),
    ?assertEqual({ok, Cmd}, archive_tender_profile_v1:from_map(archive_tender_profile_v1:to_map(Cmd))),
    ?assertEqual({error, invalid_tender_profile_archive}, archive_tender_profile_v1:from_map(#{})).

%%% @doc The tenders group's distributor, as far as it runs without a mesh:
%%% it starts nothing until the org key is known, a pull with no distributor
%%% is refused by the name a member's keyring gives it, and the realm key's id
%%% is the one the realm's endorsements are signed under.
-module(mcl_tenders_group_keys_tests).

-include_lib("eunit/include/eunit.hrl").

no_org_key_no_distributor_test() ->
    Old = os:getenv("MCL_GROUP_ORG_KEY_ID"),
    os:putenv("MCL_GROUP_ORG_KEY_ID", ""),
    try ?assertEqual(ignore, mcl_tenders_group_keys:start_link())
    after restore(Old)
    end.

restore(false) -> os:unsetenv("MCL_GROUP_ORG_KEY_ID");
restore(V) -> os:putenv("MCL_GROUP_ORG_KEY_ID", V).

a_pull_without_a_distributor_is_refused_by_name_test() ->
    undefined = whereis(mcl_tenders_group_keys),
    ?assertEqual({error, no_distributor, st},
                 mcl_tenders_group_keys_pull:handle_request(#{}, st)).

%% The membership check matches the endorsement's signer by key id, so the id
%% derived from the realm key mcl_om holds (hex) must be macula's own key id of
%% that key: a different id would refuse every member while /health said ok.
the_realm_key_id_is_macula_s_key_id_of_the_realm_key_test() ->
    {ok, RealmKey} = macula_node_keys:generate(realm, pq_hybrid),
    Hex = binary:encode_hex(macula_node_keys:public_key(RealmKey)),
    ?assertEqual(macula_node_keys:key_id(RealmKey),
                 mcl_tenders_group_keys:realm_key_id(Hex, pq_hybrid)).

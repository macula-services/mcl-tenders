%%% @doc T2: who may call the profile's procedures, decided by macula's own gate.
%%%
%%% Each procedure declares `{callers, role}' and `confidential => required'
%%% (mcl_tenders_service). macula resolves `{callers, role}' against the realm
%%% key the pool pinned into `{realm_member_required, RealmKeyId, <<"rpc/call">>}'
%%% (macula.erl, advertise/5; macula's own role_demands_the_call_capability_test
%%% pins that mapping, which macula exports to its own tests only), and its link
%%% runs that policy through macula_ucan:authorize/3 on every inbound call,
%%% before the handler. So this suite runs the same verifier, on the procedure
%%% names mcl_om advertises, with the tokens each kind of caller would carry:
%%%
%%%   - an identity the realm's tenders role granted the procedure: admitted;
%%%   - a realm member without the role (the bare membership token): refused;
%%%   - a role grant for the other procedure: refused;
%%%   - anything from another realm, signed by its key: refused.
%%%
%%% The clear call is refused by the link because the advertisement is
%%% `required'; this suite holds the options mcl_om hands macula to that, and
%%% holds mcl_om's boot check, which refuses `required' without kem_advertise.
-module(mcl_tenders_callers_tests).

-include_lib("eunit/include/eunit.hrl").

-define(REALM_NAME, <<"io.example">>).
-define(OTHER_REALM_NAME, <<"io.other">>).
-define(ORG, <<"mcl-tenders">>).
-define(CALL, <<"rpc/call">>).
-define(PROFILE, pq_hybrid).

callers_test_() ->
    {setup, fun parties/0,
     fun(P) ->
         lists:append([per_procedure(Name, Other, P) || {Name, Other} <- pairs()])
     end}.

%% Each procedure with the other one, whose grant must not admit it.
pairs() ->
    [Describe, Get] = [N || #{name := N} <- mcl_tenders_service:capabilities()],
    [{Describe, Get}, {Get, Describe}].

per_procedure(Name, Other, #{realm_key := RealmKey, other_realm_key := OtherKey,
                             holder_id := Caller}) ->
    Procedure = mcl_om_capabilities:org_procedure(?ORG, Name),
    Gate = {realm_member_required, macula_node_keys:key_id(RealmKey, ?PROFILE), ?CALL},
    Role = mint(RealmKey, Caller, proc_mri(?REALM_NAME, Procedure), ?CALL),
    Member = mint(RealmKey, Caller, <<"mri:realm:", ?REALM_NAME/binary>>, <<"member/email-verified">>),
    OtherGrant = mint(RealmKey, Caller,
                      proc_mri(?REALM_NAME, mcl_om_capabilities:org_procedure(?ORG, Other)), ?CALL),
    ForeignHere = mint(OtherKey, Caller, proc_mri(?REALM_NAME, Procedure), ?CALL),
    ForeignThere = mint(OtherKey, Caller, proc_mri(?OTHER_REALM_NAME, Procedure), ?CALL),
    [{binary_to_list(Name), ?_assertMatch({ok, _}, verdict(Role, Gate, Procedure, Caller))},
     {binary_to_list(Name), ?_assertMatch({error, _}, verdict(Member, Gate, Procedure, Caller))},
     {binary_to_list(Name), ?_assertMatch({error, _}, verdict(OtherGrant, Gate, Procedure, Caller))},
     {binary_to_list(Name), ?_assertMatch({error, _}, verdict(ForeignHere, Gate, Procedure, Caller))},
     {binary_to_list(Name), ?_assertMatch({error, _}, verdict(ForeignThere, Gate, Procedure, Caller))},
     %% The role's grant is the caller's own: another node presenting it is
     %% not its audience.
     {binary_to_list(Name), ?_assertMatch({error, _}, verdict(Role, Gate, Procedure, <<16#ee:256>>))}].

%% Every capability asks macula for exactly the gate and the seal above, in the
%% options mcl_om builds for macula:advertise/5.
every_procedure_is_advertised_role_gated_and_sealed_test() ->
    [?assertEqual({Name, #{auth => {callers, role}}, #{confidential => required}},
                  {Name, mcl_om_capabilities:auth_opts(Cap), mcl_om_capabilities:confidentiality_opts(Cap)})
     || #{name := Name} = Cap <- mcl_tenders_service:capabilities()].

%% `required' with the KEM key named boots; without it mcl_om refuses to boot
%% rather than serve the profile in the clear.
a_sealed_procedure_without_the_kem_key_does_not_boot_test() ->
    Caps = mcl_tenders_service:capabilities(),
    ?assertEqual(ok, mcl_om_capabilities:confidentiality_verdict(Caps, enabled)),
    ?assertMatch({error, {mcl_om_confidential_required_without_kem_advertise, _}},
                 mcl_om_capabilities:confidentiality_verdict(Caps, disabled)).

%%--------------------------------------------------------------------
%% Fixtures
%%--------------------------------------------------------------------

parties() ->
    {ok, RealmKey} = macula_node_keys:generate(realm, ?PROFILE, #{}),
    {ok, OtherKey} = macula_node_keys:generate(realm, ?PROFILE, #{}),
    {ok, HolderKey} = macula_node_keys:generate(identity, ?PROFILE, #{puzzle_difficulty => 0}),
    {ok, HolderId} = macula_node_keys:node_id(HolderKey),
    #{realm_key => RealmKey, other_realm_key => OtherKey, holder_id => HolderId}.

proc_mri(RealmName, Procedure) -> <<"mri:proc:", RealmName/binary, "/", Procedure/binary>>.

mint(Key, Audience, With, Can) ->
    macula_ucan:create(Key, Audience, [#{with => With, can => Can}],
                       #{exp => erlang:system_time(second) + 3_600}).

verdict(Token, Policy, Procedure, Caller) ->
    macula_ucan:authorize(Token, Policy,
                          #{caller => Caller, profile => ?PROFILE,
                            now => erlang:system_time(second),
                            realm => crypto:hash(sha256, ?REALM_NAME), procedure => Procedure,
                            proofs => #{}}).

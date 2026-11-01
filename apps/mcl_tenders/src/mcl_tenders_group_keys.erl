%% @doc The tenders group's distributor: macula's `macula_group_keys' started
%% for the org `mcl-tenders' in this realm, registered as
%% `mcl_tenders_group_keys' so the pull handler (mcl_tenders_group_keys_pull)
%% finds it by name. The realm runs its own; no other service is needed.
%%
%% WHAT IT HOLDS: the group's epoch keys, in memory only, rotated every 15
%% minutes. It is not in the data path: a member holding the current epoch
%% goes on publishing and opening while it restarts. The image writes no crash
%% dump, which would copy the heaps the keys pass through.
%%
%% WHO IS ADMITTED, INTERIM (macula-services/mcl-om#48): the org's `group_keys'
%% grant, checked against the org key `MCL_GROUP_ORG_KEY_ID' names, and then a
%% live membership of this realm, read from the realm's slot over the mesh
%% pool. The seal policy is `required': under the prefix, this node refuses
%% clear events on every subscription. Once mcl_om presents the membership
%% UCAN, the group becomes `{realm_capability, RealmKeyId, refusing}'.
%%
%% WITHOUT THE ORG KEY ID NOTHING STARTS: `ignore', so the supervisor holds no
%% child, group_keys_v1 is not advertised, and the sensor stays idle
%% (tender_notices_group:missing/0). The realm mints the org key when it
%% issues the provider grant, so on a first boot the id is not known yet.
-module(mcl_tenders_group_keys).

-export([start_link/0, options/1, realm_key_id/2]).

-define(POOL, mcl_om_mesh_pool).

-spec start_link() -> {ok, pid()} | ignore | {error, term()}.
start_link() ->
    starting(tender_notices_group:org_key_id()).

starting(undefined) ->
    ignore;
starting(OrgKeyId) ->
    started(macula_group_keys:start_link(options(OrgKeyId))).

%% A restart after a crash finds the name free: a dead process frees it.
started({ok, Pid}) ->
    true = register(?MODULE, Pid),
    {ok, Pid};
started(Error) ->
    Error.

%% @doc The distributor's options for the org key `OrgKeyId'. Everything here
%% is public material: the realm, its key's id, the org's key id. A missing
%% piece stops the boot here, never at the first pull.
-spec options(<<_:256>>) -> macula_group_keys:options().
options(OrgKeyId) ->
    {ok, Profile} = macula_crypto_profile:configured(),
    {ok, Realm} = mcl_om:realm(),
    {ok, RealmKey} = application:get_env(mcl_om, realm_key),
    #{org => tender_notices_group:org(),
      policy => required,
      org_key_id => OrgKeyId,
      realm => Realm,
      realm_key_id => realm_key_id(RealmKey, Profile),
      profile => Profile,
      pool => pool()}.

%% @doc The id of the realm's signing key, from the hex form mcl_om holds: the
%% key the realm signs its member endorsements with, which the membership
%% check verifies against.
-spec realm_key_id(binary(), macula_crypto_profile:profile()) -> <<_:256>>.
realm_key_id(RealmKeyHex, Profile) ->
    macula_node_keys:key_id(binary:decode_hex(RealmKeyHex), Profile).

%% The pool by its registered name, which the SDK looks up at every membership
%% read, so a pool mcl_om's supervisor restarts is found again.
pool() ->
    pooled(whereis(?POOL)).

pooled(undefined) -> error({mcl_tenders_group_keys, pool_not_started});
pooled(_Pid) -> ?POOL.

%% @doc The mcl_om service contract: what this service is and may do.
%%
%% SIX CALLBACKS, ALL REQUIRED. mcl_om resolves them BY NAME at startup, on a
%% live node, so a service that forgets one dies with `undef' where nobody is
%% watching. The `-behaviour' attribute below is what turns that into a compile
%% error instead, and the test suite guards the attribute itself.
%%
%% ONE RELEASE PER REALM (architecture/README.md). It keeps the realm's tenders
%% profile on this node and answers for it only to the identities the realm
%% granted the tenders role. It asks the realm for no topic authority: its
%% procedures are CALLs, served under the realm's org-wide provider grant for
%% mcl-tenders.
-module(mcl_tenders_service).

-behaviour(mcl_om_service).

-export([info/0, start/1, stop/1, health/0, capabilities/0, identity_spec/0]).
%% ==========================================================================
%% AND THE STORE THIS SERVICE OWNS
%% ==========================================================================
%%
%% NOT an mcl_om callback: mcl_om opens no store since 0.35.0. mcl_tenders_app
%% reads it and opens the store in its own start/2 before mcl_om:boot/1, with
%% reckon_db, evoq and reckon_evoq declared by this service in rebar.config and
%% its app.src.
%%
%% ⚠ ONE MAP, NOT THE OLD `store_id/0' AND `data_dir/0' CALLBACKS. mcl_om 0.35
%% warns at every boot about a service module exporting those two together,
%% because that is how a service built for the old contract looks, and a false
%% warning teaches everyone to ignore the true one.
%%
%% ⚠ `config/sys.config.src' MUST CARRY THE `evoq' BLOCK. The per-store evoq
%% subscription reads the global log, and that crashes on
%% `{not_configured, event_store_adapter}' without it. evoq starts as a
%% release-boot application before any service's `start/2' runs, so nothing can
%% inject it later. A sibling put two of three fleet nodes into a boot-crash
%% loop this exact way.
-export([event_store/0]).

info() ->
    #{name => <<"mcl-tenders">>,
      version => <<"0.1.0">>,
      description => <<"Public tenders that fit a realm's profile, guided from spotted to bid on the realm's own node">>}.

%% The realm's profile is born the first time mcl-tenders boots in the realm,
%% and is already there on every boot after. The store is open (mcl_tenders_app)
%% and the projections listen (project_tenders) by the time this runs.
start(_Opts) ->
    {ok, Realm} = mcl_om:realm(),
    ok = maybe_initiate_tender_profile:for_realm(Realm),
    mcl_tenders_sup:start_link().

stop(_State) -> ok.

%% Green once the supervision tree is up. A dark mesh is not a health failure:
%% the profile stays readable in process, and a restart would not light it.
health() -> ok.

%% WHAT THIS SERVICE ANNOUNCES IT CAN DO. Each is a CALL answered by
%% <name>_responder; README, "Procedures", is the contract.
capabilities() ->
    [procedure(Name) || Name <- [<<"describe_tender_profile">>, <<"get_tender_profile">>]].

%% THE GATE (T2). `{callers, role}': only an identity holding a capability the
%% realm's tenders role minted for the procedure is admitted -- not a bare
%% member, not a node of another realm -- and macula's link decides that
%% before the handler runs. `confidential => required': the node names its KEM
%% key (kem_advertise in sys.config) and the link refuses a call in the clear,
%% so the profile crosses a station only as ciphertext.
procedure(Name) ->
    #{name => Name, version => 1, confidential => required, auth => {callers, role},
      handler => {binary_to_atom(<<Name/binary, "_responder">>), []}}.

%% THE AUTHORITY THIS SERVICE ASKS THE REALM FOR, and deliberately nothing more.
%% It publishes and subscribes to nothing yet, so it asks for nothing. Popped,
%% an attacker gains precisely this and no more, which is the whole point of
%% listing it.
identity_spec() ->
    #{scope => <<"mcl-tenders">>,
      actions => [],
      resources => [],
      ttl_days => 30}.

%% ==========================================================================
%% The store
%% ==========================================================================

%% @doc The reckon-db store this service owns, as mcl_tenders_app opens it.
%%
%% `id': ⚠ IT IS NAMED IN TWO PLACES, here and in the `evoq' block of
%% `config/sys.config.src', and nothing makes them agree by itself. Disagreeing
%% opens one store and addresses another. A test compares the two.
%%
%% `dir': where it lives on disk (the store itself at <dir>/<id>/). The image
%% sets MCL_DATA_DIR to its /data volume and the compose file mounts that on a
%% bulk drive; the /tmp default is for a laptop.
%%
%% `indexes': none until a query needs one. `mode': `single', one node's
%% store. `integrity': `disabled', or per-store HMAC tamper-resistance once a
%% key is provisioned.
-spec event_store() -> #{id := atom(), dir := string(), indexes := [term()],
                         mode := single | cluster, integrity := disabled | map()}.
event_store() ->
    #{id => mcl_tenders_store,
      dir => chosen(os:getenv("MCL_DATA_DIR")),
      indexes => [],
      mode => single,
      integrity => disabled}.

chosen(false) -> "/tmp/mcl_tenders";
chosen("") -> "/tmp/mcl_tenders";
chosen(Path) -> Path.

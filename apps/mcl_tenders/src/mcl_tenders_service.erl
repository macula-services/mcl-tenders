%% @doc The mcl_om service contract: what this service is and may do.
%%
%% SIX CALLBACKS, ALL REQUIRED. mcl_om resolves them BY NAME at startup, on a
%% live node, so a service that forgets one dies with `undef' where nobody is
%% watching. The `-behaviour' attribute below is what turns that into a compile
%% error instead, and the test suite guards the attribute itself.
%%
%% ONE RELEASE PER REALM (architecture/README.md). It keeps the realm's tenders
%% profile on this node and answers for it only to the identities the realm
%% granted the tenders role; its sensor asks TED for the profile's CPV codes
%% and countries and reports each new notice sealed under the realm's tenders
%% group, whose keys this node serves itself. Its procedures are CALLs, served
%% under the realm's org-wide provider grant for mcl-tenders.
-module(mcl_tenders_service).

-behaviour(mcl_om_service).

-export([info/0, start/1, stop/1, health/0, capabilities/0, identity_spec/0,
         subscriptions/0]).
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

%% `sealing' says whether the deploy has set up the tenders group (`set') or
%% not yet (`unset'), in the /health body while the verdict stays ok: a first
%% boot waits on the realm for the org key, which is a setup state, not a
%% fault. The variables it waits on are named in the log, never their values.
%%
%% `intake' is today's count of spotted tenders, the drops past the day's cap
%% and the cap itself (T12); `sensor' is whether the sensor sweeps or idles,
%% the idle reason as a tag only, and when it last finished a whole sweep;
%% `quiet' is 1 while the sensor idles or has not finished a sweep in a day,
%% so a quiet stream is not mistaken for a quiet TED (T5). Counts and times,
%% never a notice or a profile.
info() ->
    #{name => <<"mcl-tenders">>,
      version => <<"0.1.1">>,
      description => <<"Public tenders that fit a realm's profile, guided from spotted to bid on the realm's own node">>,
      sealing => sealing(tender_notices_group:missing()),
      intake => intake(tender_intake:today()),
      sensor => sensor(sense_ted_notices:status()),
      quiet => quiet(sense_ted_notices:status(), erlang:system_time(millisecond))}.

sealing([]) -> set;
sealing(_Missing) -> unset.

intake({ok, #{spotted := Spotted, dropped := Dropped, cap := Cap, last_notice_at := Last}}) ->
    #{spotted => Spotted, dropped => Dropped, cap => Cap, last_notice_at => Last};
intake({error, unavailable}) -> unavailable.

sensor({ok, #{state := State, idle_reason := Why, last_swept_at := At}}) ->
    #{state => State, idle_reason => reason_tag(Why), last_swept_at => At};
sensor({error, unavailable}) -> unavailable.

%% The tag of an idle reason; its detail (a store error, the unset variable
%% names) stays in the log.
reason_tag(Why) when is_atom(Why) -> Why;
reason_tag(Why) when is_tuple(Why), is_atom(element(1, Why)) -> element(1, Why);
reason_tag(_Why) -> other.

-define(QUIET_AFTER_MS, 24 * 3600 * 1000).

quiet({ok, #{state := sweeping, last_swept_at := At}}, Now) when Now - At < ?QUIET_AFTER_MS -> 0;
quiet(_Status, _Now) -> 1.

%% The realm's profile is born the first time mcl-tenders boots in the realm,
%% and is already there on every boot after. The store is open (mcl_tenders_app)
%% and the projections listen (project_tenders) by the time this runs.
%%
%% The realm name the fact topic and the group carry is checked against the
%% realm first: a sensor reporting where nobody subscribed looks exactly like
%% a quiet day at TED.
start(_Opts) ->
    ok = mcl_tenders_facts:check_realm_name(),
    {ok, Realm} = mcl_om:realm(),
    ok = maybe_initiate_tender_profile:for_realm(Realm),
    ok = naming_the_wait(tender_notices_group:missing()),
    mcl_tenders_sup:start_link().

%% Once at boot, so the wait is findable: the variables by name, never a value.
naming_the_wait([]) ->
    ok;
naming_the_wait(Missing) ->
    logger:notice("[tenders] the tenders group is not set up, so no group key is served and the "
                  "sensor stays idle; unset: ~ts (macula-services/mcl-om#48)",
                  [lists:join(", ", Missing)]).

stop(_State) -> ok.

%% WHAT THIS SERVICE LISTENS TO: the sensor's fact, so each reported notice
%% reaches the process manager that may spot a tender (the morning list).
%% Sealed under the realm's tenders group: mcl_om calls the admission once per
%% subscribe attempt and hands the token straight to macula, so it sits in no
%% child spec, state or log (mcl_om 1.7.0, mcl-om#49). Its sources are the
%% realm's `mcl-tenders' org (T4): the realm's own sensors, whatever their node
%% ids, and nobody else.
%%
%% Declared only once the group is set up, the way the sensor idles until
%% then: a subscription declared without its admission would hold /health
%% degraded for what is a setup state, not a fault (info's `sealing'). Pure:
%% read from the environment and app env, as mcl_om requires.
subscriptions() ->
    subscribed(tender_notices_group:missing()).

subscribed([]) ->
    RealmName = mcl_tenders_facts:realm_name(),
    [#{topic => mcl_tenders_facts:topic(RealmName),
       module => on_tender_notice_reported_v1_maybe_spot_tender,
       sources => {org, tender_notices_group:org()},
       group => tender_notices_group:prefix(RealmName),
       admission => {tender_notices_group, admission, []}}];
subscribed(_Missing) ->
    [].

%% Green once the supervision tree is up. A dark mesh is not a health failure:
%% the profile stays readable in process, and a restart would not light it.
%% Nor is TED being unreachable (the sweep backs off), nor the group waiting
%% on its setup (info's `sealing').
health() -> ok.

%% WHAT THIS SERVICE ANNOUNCES IT CAN DO. The profile's and the dossiers'
%% procedures are CALLs answered by <name>_responder; README, "Procedures", is the contract. And,
%% once the org key id is known, the tenders group's distributor.
capabilities() ->
    [procedure(Name) || Name <- [<<"describe_tender_profile">>, <<"get_tender_profile">>,
                                 <<"archive_tender_profile">>, <<"get_tenders_page">>, <<"get_tender_by_id">>,
                                 <<"dismiss_tender">>]]
        ++ group_keys(tender_notices_group:org_key_id()).

%% macula's advertise_opts/0: `auth => handler_authorizes', which runs no gate
%% at the link and hands the handler the call's token and proofs, and
%% `confidential => required', so a key never travels readable by a station.
group_keys(undefined) ->
    [];
group_keys(_OrgKeyId) ->
    [maps:merge(#{name => <<"group_keys_v1">>, version => 1,
                  handler => {mcl_tenders_group_keys_pull, []}},
                macula_group_keys:advertise_opts())].

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
%% Its one fact travels sealed under the tenders group, and who may read it is
%% the group's admission, not a realm topic right; a realm role carries no
%% publish right at all (macula#147). So it asks for nothing. Popped, an
%% attacker gains precisely this and no more.
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

%%% @doc The realm's tenders group: the sealed group `tender_notice_reported_v1'
%%% travels under, inside the realm, from the sensor to guide_tender_lifecycle.
%%%
%%% WHY SEALED. The sensor asks TED only for the profile's CPV codes and
%%% countries, so its stream of facts IS the realm's matches. Under the group
%%% the stations on the path see one topic, who published and when, and never
%%% a payload (macula's sealed groups, PUBSUB_GUIDE "Sealed groups").
%%%
%%% THE GROUP is the prefix `<realm name>/mcl-tenders/tenders', owned by the org
%%% `mcl-tenders', whose distributor this release runs itself
%%% (mcl_tenders_group_keys): no other service is needed.
%%%
%%% ADMISSION, INTERIM (macula-services/mcl-om#48). A node pulls the group's key
%%% with the org's `group_keys' grant: a UCAN the org key signs for that node,
%%% which the realm operator mints by hand today and the deploy hands over as
%%% `MCL_TENDERS_GROUP_UCAN'. The distributor checks it against the org key,
%%% `MCL_GROUP_ORG_KEY_ID'. When mcl_om presents the node's membership UCAN to
%%% a group pull, the group becomes `{realm_capability, RealmKeyId, refusing}'
%%% (the realm's tenders role) and the hand-minted token goes.
%%%
%%% FAIL CLOSED. Without either variable the setup is `missing/0', the sensor
%%% does not sweep, and nothing is ever published in the clear: a publish under
%%% the prefix without the group is refused by macula itself.
%%%
%%% THE TOKEN IS NEVER LOGGED. It is read from the environment at the moment of
%%% a publish, held in no process state, and no function here returns it in a
%%% form a log line or an error term would print.
-module(tender_notices_group).

-export([org/0, prefix/1, missing/0, org_key_id/0, admission/0, publish_opts/2, publish_opts/3]).

-define(ORG, <<"mcl-tenders">>).
-define(TOKEN_VAR, "MCL_TENDERS_GROUP_UCAN").
-define(ORG_KEY_VAR, "MCL_GROUP_ORG_KEY_ID").

-type publish5() :: fun((pid(), binary(), binary(), term(), map()) -> ok | {error, term()}).

%% @doc The org that owns the group, and serves its keys.
-spec org() -> binary().
org() -> ?ORG.

%% @doc The group's prefix in the realm named `RealmName': every topic below it
%% on a segment boundary is sealed under the group.
-spec prefix(binary()) -> binary().
prefix(RealmName) -> <<RealmName/binary, "/", ?ORG/binary, "/tenders">>.

%% @doc The variables the deploy has not set, by name: `[]' when the node can
%% seal. A name, never a value.
-spec missing() -> [string()].
missing() ->
    [Var || {Var, Set} <- [{?TOKEN_VAR, token() =/= undefined},
                           {?ORG_KEY_VAR, org_key_id() =/= undefined}],
            not Set].

%% @doc The org key's id, or `undefined' until the deploy names it: exactly 64
%% hex characters, or the boot stops naming the variable, because a short id
%% matches nothing and every pull would be refused while /health says ok.
-spec org_key_id() -> <<_:256>> | undefined.
org_key_id() ->
    hex_32(os:getenv(?ORG_KEY_VAR, "")).

hex_32("") -> undefined;
hex_32(Hex) when length(Hex) =:= 64 -> decoded(catch binary:decode_hex(list_to_binary(Hex)));
hex_32(_WrongLength) -> error({mcl_tenders_group, {not_64_hex, ?ORG_KEY_VAR}}).

decoded(<<_:256>> = Id) -> Id;
decoded(_NotHex) -> error({mcl_tenders_group, {not_64_hex, ?ORG_KEY_VAR}}).

%% @doc The admission token a subscription under the group presents, read at
%% the moment mcl_om asks for it (once per subscribe attempt), so it sits in
%% no state: `{ok, Token}', or `{error, no_admission_token}' while the deploy
%% has not set it, which mcl_om names on /health without the value.
-spec admission() -> {ok, binary()} | {error, no_admission_token}.
admission() -> admitting(token()).

admitting(undefined) -> {error, no_admission_token};
admitting(Token) -> {ok, Token}.

%% @doc mcl_om_pubsub's options for one sealed publish under the group of
%% `RealmName', through macula:publish/5.
-spec publish_opts(binary(), map()) -> map().
publish_opts(RealmName, Opts) ->
    publish_opts(RealmName, Opts, fun macula:publish/5).

%% @doc As publish_opts/2 with the publish function given, so a test sees what
%% reaches macula. One frame, no start and completed announcements: they would
%% be clear publishes under the prefix, which macula refuses.
-spec publish_opts(binary(), map(), publish5()) -> map().
publish_opts(RealmName, Opts, Publish) ->
    Prefix = prefix(RealmName),
    Opts#{publisher_opts => #{announce => false,
                              publish => fun(Pool, Realm, Topic, Payload) ->
                                                 sealed(Publish, Pool, Realm, Topic, Payload, Prefix)
                                         end}}.

%% The token is read here, at the publish, so it sits in no state and no
%% closure a crash report could print.
sealed(Publish, Pool, Realm, Topic, Payload, Prefix) ->
    admitted(token(), Publish, Pool, Realm, Topic, Payload, Prefix).

admitted(undefined, _Publish, _Pool, _Realm, _Topic, _Payload, _Prefix) ->
    {error, {group, no_admission_token}};
admitted(Token, Publish, Pool, Realm, Topic, Payload, Prefix) ->
    Publish(Pool, Realm, Topic, Payload, #{group => Prefix, ucan_token => Token}).

token() -> token(os:getenv(?TOKEN_VAR, "")).

token("") -> undefined;
token(Token) -> list_to_binary(Token).

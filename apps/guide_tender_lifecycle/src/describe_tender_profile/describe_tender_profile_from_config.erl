%%% @doc The node's operator describes the realm's profile from config, at boot.
%%%
%%% This exists so a realm's tenders node can start looking for tenders with no
%%% realm role and no call over the mesh: its deployment names what to look
%%% for, and the node describes it once.
%%%
%%% `MCL_TENDERS_PROFILE_CPV' and `MCL_TENDERS_PROFILE_COUNTRIES', each a
%%% comma-separated list (CPV codes of eight digits; ISO 3166-1 alpha-3
%%% countries such as BEL). Both unset: nothing happens. Set, they become one
%%% describe_tender_profile_v1 with `unless_described = 1', dispatched through
%%% maybe_describe_tender_profile:dispatch/1, so the command's checks, the
%%% aggregate's rules and the event are the ones a CALL gets. The aggregate
%%% applies it only to a profile never described: one the realm described over
%%% the mesh is kept, and so is one an earlier boot described. `described_by'
%%% is the node's own id.
%%%
%%% It never stops the boot. A refusal (a bad code, one variable without the
%%% other, an archived profile) is logged by its reason tag; the log names
%%% counts and reasons, never a profile term (T8).
%%% @end
-module(describe_tender_profile_from_config).

-export([at_boot/2, described/3, command/3]).

-define(CPV_VAR, "MCL_TENDERS_PROFILE_CPV").
-define(COUNTRIES_VAR, "MCL_TENDERS_PROFILE_COUNTRIES").

-type env() :: fun((string()) -> false | string()).

%% @doc Describes Realm's profile from Env (os:getenv/1 on a node), if the
%% config names one and the profile was never described. Always `ok'.
-spec at_boot(<<_:256>>, env()) -> ok.
at_boot(Realm, Env) ->
    described(Realm, own_node_id(mcl_om:identity_key()), Env).

%% @doc at_boot/2 with the describing node's id given.
-spec described(<<_:256>>, binary() | undefined, env()) -> ok.
described(Realm, NodeId, Env) ->
    reported(dispatched(command(Realm, NodeId, Env))).

%% @doc The command the config stands for: `off' when it names no profile.
-spec command(<<_:256>>, binary() | undefined, env()) ->
          off | {ok, describe_tender_profile_v1:t()} | {error, atom()}.
command(Realm, NodeId, Env) ->
    configured(listed(Env(?CPV_VAR)), listed(Env(?COUNTRIES_VAR)), Realm, NodeId).

listed(false) -> unset;
listed("") -> unset;
listed(Text) -> [unicode:characters_to_binary(string:trim(Item)) || Item <- string:split(Text, ",", all)].

configured(unset, unset, _Realm, _NodeId) ->
    off;
configured(unset, _Countries, _Realm, _NodeId) ->
    {error, profile_cpv_unset};
configured(_Cpv, unset, _Realm, _NodeId) ->
    {error, profile_countries_unset};
configured(Cpv, Countries, Realm, NodeId) ->
    describe_tender_profile_v1:new(#{realm => Realm, described_by => NodeId,
                                     cpv_codes => Cpv, countries => Countries,
                                     unless_described => 1}).

own_node_id({ok, Key}) -> held(macula_node_keys:node_id(Key));
own_node_id({error, _}) -> undefined.

held({ok, <<_:256>> = NodeId}) -> NodeId;
held(_NoId) -> undefined.

dispatched(off) -> off;
dispatched({ok, Cmd}) -> {Cmd, maybe_describe_tender_profile:dispatch(Cmd)};
dispatched({error, _} = Refused) -> Refused.

reported(off) ->
    ok;
reported({Cmd, {ok, _Version, _Events}}) ->
    #{cpv_codes := Cpv, countries := Countries} = describe_tender_profile_v1:fields(Cmd),
    logger:notice("[tenders] described the realm's profile from config at boot: "
                  "~b CPV codes, ~b countries", [length(Cpv), length(Countries)]);
reported({_Cmd, {error, already_described}}) ->
    logger:notice("[tenders] the realm's profile is described already; "
                  "the config's profile is not applied");
reported({_Cmd, {error, Reason}}) ->
    refused(Reason);
reported({error, Reason}) ->
    refused(Reason).

refused(Reason) ->
    logger:warning("[tenders] did not describe the realm's profile from config: ~p",
                   [reason_tag(Reason)]).

reason_tag(Why) when is_atom(Why) -> Why;
reason_tag(Why) when is_tuple(Why), is_atom(element(1, Why)) -> element(1, Why);
reason_tag(_Why) -> other.

%%% @doc Handler for `initiate_tender_profile_v1'.
%%%
%%% Validates the payload and builds the event. The lifecycle rules live in
%%% tender_profile_aggregate.
%%%
%%% for_realm/1 is how the profile is born: mcl_tenders_service:start/1 calls
%%% it on every boot, and a profile already there is the answer it wants.
%%% @end
-module(maybe_initiate_tender_profile).

-export([handle_from_map/1, handle/1, dispatch/1, for_realm/1]).

-include_lib("evoq/include/evoq.hrl").

-spec handle_from_map(map()) -> {ok, [map()]} | {error, term()}.
handle_from_map(Payload) ->
    handled(initiate_tender_profile_v1:from_map(Payload)).

-spec handle(initiate_tender_profile_v1:t()) -> {ok, [map()]} | {error, term()}.
handle(Cmd) ->
    built(initiate_tender_profile_v1:validate(Cmd), Cmd).

%% @doc The realm's profile exists once this returns ok, whether this call
%% initiated it or an earlier boot did.
-spec for_realm(<<_:256>>) -> ok | {error, term()}.
for_realm(Realm) ->
    initiated(dispatched(initiate_tender_profile_v1:new(#{realm => Realm}))).

dispatched({ok, Cmd}) -> dispatch(Cmd);
dispatched({error, _} = E) -> E.

initiated({ok, _Version, _Events}) -> ok;
initiated({error, already_initiated}) -> ok;
initiated({error, _} = E) -> E.

%% @doc Dispatches through evoq, which runs the aggregate and persists the
%% event in mcl_tenders_store.
-spec dispatch(initiate_tender_profile_v1:t()) ->
          {ok, non_neg_integer(), [map()]} | {error, term()}.
dispatch(Cmd) ->
    EvoqCmd = #evoq_command{
        command_type = initiate_tender_profile_v1,
        aggregate_type = tender_profile_aggregate,
        aggregate_id = initiate_tender_profile_v1:stream_id(Cmd),
        payload = initiate_tender_profile_v1:to_map(Cmd),
        metadata = #{timestamp => erlang:system_time(millisecond)}
    },
    evoq_command_router:dispatch(EvoqCmd, #{
        store_id => tender_profile_aggregate:store_id(),
        adapter => reckon_evoq_adapter,
        consistency => eventual
    }).

handled({ok, Cmd}) -> handle(Cmd);
handled({error, _} = E) -> E.

built(ok, Cmd) ->
    Event = tender_profile_initiated_v1:new(#{realm => initiate_tender_profile_v1:get_realm(Cmd)}),
    {ok, [tender_profile_initiated_v1:to_map(Event)]}.

%%% @doc Handler for `describe_tender_profile_v1'.
%%%
%%% Validates the payload and builds the event. The lifecycle rules live in
%%% tender_profile_aggregate.
%%% @end
-module(maybe_describe_tender_profile).

-export([handle_from_map/1, handle/1, dispatch/1]).

-include_lib("evoq/include/evoq.hrl").

-spec handle_from_map(map()) -> {ok, [map()]} | {error, term()}.
handle_from_map(Payload) ->
    handled(describe_tender_profile_v1:from_map(Payload)).

-spec handle(describe_tender_profile_v1:t()) -> {ok, [map()]} | {error, term()}.
handle(Cmd) ->
    built(describe_tender_profile_v1:validate(Cmd), Cmd).

%% @doc Dispatches through evoq, which runs the aggregate and persists the
%% event in mcl_tenders_store.
-spec dispatch(describe_tender_profile_v1:t()) ->
          {ok, non_neg_integer(), [map()]} | {error, term()}.
dispatch(Cmd) ->
    EvoqCmd = #evoq_command{
        command_type = describe_tender_profile_v1,
        aggregate_type = tender_profile_aggregate,
        aggregate_id = describe_tender_profile_v1:stream_id(Cmd),
        payload = describe_tender_profile_v1:to_map(Cmd),
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
    #{realm := Realm, described_by := By} = describe_tender_profile_v1:to_map(Cmd),
    Event = tender_profile_described_v1:new(
              maps:merge(#{realm => Realm, described_by => By},
                         describe_tender_profile_v1:fields(Cmd))),
    {ok, [tender_profile_described_v1:to_map(Event)]}.

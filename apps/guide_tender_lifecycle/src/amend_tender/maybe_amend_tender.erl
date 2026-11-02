%%% @doc Handler for `amend_tender_v1'.
%%%
%%% Validates the payload and builds the event. The lifecycle rules live in
%%% tender_aggregate.
%%% @end
-module(maybe_amend_tender).

-export([handle_from_map/1, handle/1, dispatch/1]).

-include_lib("evoq/include/evoq.hrl").

-spec handle_from_map(map()) -> {ok, [map()]} | {error, term()}.
handle_from_map(Payload) ->
    handled(amend_tender_v1:from_map(Payload)).

-spec handle(amend_tender_v1:t()) -> {ok, [map()]} | {error, term()}.
handle(Cmd) ->
    built(amend_tender_v1:validate(Cmd), Cmd).

%% @doc Dispatches through evoq, which runs the aggregate and persists the
%% event in mcl_tenders_store.
-spec dispatch(amend_tender_v1:t()) -> {ok, non_neg_integer(), [map()]} | {error, term()}.
dispatch(Cmd) ->
    EvoqCmd = #evoq_command{
        command_type = amend_tender_v1,
        aggregate_type = tender_aggregate,
        aggregate_id = amend_tender_v1:stream_id(Cmd),
        payload = amend_tender_v1:to_map(Cmd),
        metadata = #{timestamp => erlang:system_time(millisecond)}
    },
    evoq_command_router:dispatch(EvoqCmd, #{
        store_id => tender_aggregate:store_id(),
        adapter => reckon_evoq_adapter,
        consistency => eventual
    }).

handled({ok, Cmd}) -> handle(Cmd);
handled({error, _} = E) -> E.

built(ok, Cmd) ->
    {ok, [tender_amended_v1:to_map(tender_amended_v1:new(maps:remove(command_type, amend_tender_v1:to_map(Cmd))))]}.

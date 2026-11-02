%%% @doc Handler for `note_tender_award_v1'.
%%%
%%% Validates the payload and builds the event. The lifecycle rules live in
%%% tender_aggregate.
%%% @end
-module(maybe_note_tender_award).

-export([handle_from_map/1, handle/1, dispatch/1]).

-include_lib("evoq/include/evoq.hrl").

-spec handle_from_map(map()) -> {ok, [map()]} | {error, term()}.
handle_from_map(Payload) ->
    handled(note_tender_award_v1:from_map(Payload)).

-spec handle(note_tender_award_v1:t()) -> {ok, [map()]} | {error, term()}.
handle(Cmd) ->
    built(note_tender_award_v1:validate(Cmd), Cmd).

%% @doc Dispatches through evoq, which runs the aggregate and persists the
%% event in mcl_tenders_store.
-spec dispatch(note_tender_award_v1:t()) -> {ok, non_neg_integer(), [map()]} | {error, term()}.
dispatch(Cmd) ->
    EvoqCmd = #evoq_command{
        command_type = note_tender_award_v1,
        aggregate_type = tender_aggregate,
        aggregate_id = note_tender_award_v1:stream_id(Cmd),
        payload = note_tender_award_v1:to_map(Cmd),
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
    {ok, [tender_award_noted_v1:to_map(tender_award_noted_v1:new(maps:remove(command_type, note_tender_award_v1:to_map(Cmd))))]}.

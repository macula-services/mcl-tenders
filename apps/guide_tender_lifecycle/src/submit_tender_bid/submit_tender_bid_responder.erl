%%% @doc RESPONDER for the `mcl-tenders/submit_tender_bid' procedure.
%%%
%%% The bid for a pursued tender went in. Only a caller the realm granted the
%%% tenders role reaches this handler: the capability declares
%%% `{callers, role}' and the call must be sealed (T2), and macula's link
%%% refuses everyone else before the handler runs. The open reads switch never
%%% opens it. The caller, the node id that signed the call, is recorded as
%%% `submitted_by' (T13).
%%%
%%% Payload: `tender_id' (text). Replies `#{}' once the event is stored, or
%%% `#{reason => Why}' naming the rule that refused it (README, "Procedures").
%%% @end
-module(submit_tender_bid_responder).
-behaviour(macula_response).

-export([init/1, handle_request/2, command/2]).

init(_Args) -> {ok, []}.

-spec handle_request(map(), term()) -> {reply, map(), term()}.
handle_request(Payload, State) ->
    {reply, replied(dispatched(command(mcl_om:realm(), Payload))), State}.

%% @doc The command a CALL stands for, in the realm this node serves.
-spec command({ok, binary()} | {error, term()}, map()) -> {ok, submit_tender_bid_v1:t()} | {error, atom()}.
command({ok, Realm}, Payload) ->
    submit_tender_bid_v1:new(#{realm => Realm,
                submitted_by => mcl_om_wire:caller(Payload),
                tender_id => mcl_om_wire:field(tender_id, Payload)});
command({error, _}, _Payload) ->
    {error, no_realm}.

dispatched({ok, Cmd}) -> maybe_submit_tender_bid:dispatch(Cmd);
dispatched({error, _} = Refused) -> Refused.

replied({ok, _Version, _Events}) -> #{};
replied({error, not_spotted}) -> #{reason => {text, <<"not_found">>}};
replied({error, Reason}) when is_atom(Reason) -> #{reason => {text, atom_to_binary(Reason)}};
replied({error, _Unexpected}) -> #{reason => {text, <<"internal_error">>}}.

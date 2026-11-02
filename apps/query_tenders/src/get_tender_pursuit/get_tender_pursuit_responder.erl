%%% @doc RESPONDER for the `mcl-tenders/get_tender_pursuit' procedure.
%%%
%%% The documents and questions of one spotted tender of the realm this node
%%% serves, for a caller the realm granted the tenders role: the capability
%%% declares `{callers, role}' and the call must be sealed (T2), and macula's
%%% link refuses everyone else before the handler runs. The open reads switch
%%% never opens it: these are the bid team's papers.
%%%
%%% Payload: `tender_id' (text). Replies `{documents, questions}', or
%%% `#{reason => Why}' (README, "Procedures").
%%% @end
-module(get_tender_pursuit_responder).
-behaviour(macula_response).

-export([init/1, handle_request/2]).

init(_Args) -> {ok, []}.

-spec handle_request(map(), term()) -> {reply, map(), term()}.
handle_request(Payload, State) ->
    {reply, query_tenders_reply:replied(
              of_realm(mcl_om:realm(), mcl_om_wire:field(tender_id, Payload))), State}.

of_realm({ok, Realm}, TenderId) -> get_tender_pursuit:find(Realm, TenderId);
of_realm({error, _}, _TenderId) -> {error, no_realm}.

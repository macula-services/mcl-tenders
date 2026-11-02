%%% @doc RESPONDER for the `mcl-tenders/get_tender_by_id' procedure.
%%%
%%% One spotted tender of the realm this node serves, for a caller the realm
%%% granted the tenders role: the capability declares `{callers, role}' and the
%%% call must be sealed (T2), and macula's link refuses everyone else before
%%% the handler runs. With MCL_TENDERS_OPEN_READS=1 it declares
%%% `{callers, members}' instead: every member of the realm, still sealed
%%% (mcl_tenders_service, "the open reads switch").
%%%
%%% Payload: `tender_id' (text). Replies the tender's dossier, or
%%% `#{reason => Why}' (README, "Procedures").
%%% @end
-module(get_tender_by_id_responder).
-behaviour(macula_response).

-export([init/1, handle_request/2]).

init(_Args) -> {ok, []}.

-spec handle_request(map(), term()) -> {reply, map(), term()}.
handle_request(Payload, State) ->
    {reply, query_tenders_reply:replied(
              of_realm(mcl_om:realm(), mcl_om_wire:field(tender_id, Payload))), State}.

of_realm({ok, Realm}, TenderId) -> get_tender_by_id:find(Realm, TenderId);
of_realm({error, _}, _TenderId) -> {error, no_realm}.

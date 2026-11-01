%%% @doc RESPONDER for the `mcl-tenders/get_tender_profile' procedure.
%%%
%%% The profile of the realm this node serves, for a caller the realm granted
%%% the tenders role: the capability declares `{callers, role}' and the call
%%% must be sealed (T2), and macula's link refuses everyone else before the
%%% handler runs. Payload `{}'. Replies the profile's fields, or
%%% `#{reason => Why}'.
%%% @end
-module(get_tender_profile_responder).
-behaviour(macula_response).

-export([init/1, handle_request/2]).

init(_Args) -> {ok, []}.

-spec handle_request(map(), term()) -> {reply, map(), term()}.
handle_request(_Payload, State) ->
    {reply, query_tenders_reply:replied(of_realm(mcl_om:realm())), State}.

of_realm({ok, Realm}) -> get_tender_profile:find(Realm);
of_realm({error, _}) -> {error, no_realm}.

%%% @doc RESPONDER for the `mcl-tenders/get_tenders_page' procedure.
%%%
%%% The morning list of the realm this node serves, for a caller the realm
%%% granted the tenders role: the capability declares `{callers, role}' and the
%%% call must be sealed (T2), and macula's link refuses everyone else before
%%% the handler runs.
%%%
%%% Payload: `since' (unix ms, optional), `limit' (1..100, optional) and
%%% `include_dismissed' (0 or 1, optional). Replies `#{tenders => [...], text => Text}', or
%%% `#{reason => Why}' (README, "Procedures").
%%% @end
-module(get_tenders_page_responder).
-behaviour(macula_response).

-export([init/1, handle_request/2, opts/1]).

init(_Args) -> {ok, []}.

-spec handle_request(map(), term()) -> {reply, map(), term()}.
handle_request(Payload, State) ->
    {reply, query_tenders_reply:replied(of_realm(mcl_om:realm(), opts(Payload))), State}.

%% @doc The page options a CALL asks for; an absent field keeps the desk's
%% default, a present one is checked by get_tenders_page:find/2.
-spec opts(map()) -> get_tenders_page:opts().
opts(Payload) ->
    maps:from_list([{K, V} || K <- [since, limit, include_dismissed],
                              V <- [mcl_om_wire:field(K, Payload)], V =/= undefined]).

of_realm({ok, Realm}, Opts) -> get_tenders_page:find(Realm, Opts);
of_realm({error, _}, _Opts) -> {error, no_realm}.

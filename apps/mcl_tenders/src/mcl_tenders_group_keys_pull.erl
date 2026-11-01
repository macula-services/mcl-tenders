%% @doc The `mcl-tenders/group_keys_v1' handler: every pull forwarded to the
%% live distributor (mcl_tenders_group_keys) by its registered name.
%%
%% The sealed-only channel is enforced by the link before this runs
%% (`confidential => required'). The call's authority is not: the capability is
%% advertised `auth => handler_authorizes', so the link hands the handler the
%% token the caller signed and its proofs beside `caller', and macula's handler
%% checks them per group, then live realm membership. The group a pull names
%% travels inside the sealed payload, where no gate sees it (macula#129).
%%
%% A refusal goes back as macula names it, `{error, Reason}', which the link
%% answers as `handler_error'. While the distributor restarts there is no one
%% to ask, and the pull is refused `no_distributor', the name a member's
%% keyring gives a distributor it cannot reach.
-module(mcl_tenders_group_keys_pull).

-behaviour(macula_response).

-export([init/1, handle_request/2]).

init(_Args) -> {ok, undefined}.

-spec handle_request(term(), term()) -> {reply, map(), term()} | {error, atom() | binary(), term()}.
handle_request(Payload, State) ->
    answered(pulled(whereis(mcl_tenders_group_keys), Payload), State).

pulled(undefined, _Payload) -> {error, no_distributor};
pulled(Distributor, Payload) -> (macula_group_keys:handler(Distributor))(Payload).

%% macula refuses with an atom (a membership or epoch reason) or a binary
%% (`not_authorized: <capability> on <resource>'): the handler's own error,
%% never a reply, which the member would take for a malformed key reply.
answered({error, Reason}, State) when is_atom(Reason); is_binary(Reason) ->
    {error, Reason, State};
answered(Reply, State) when is_map(Reply) ->
    {reply, Reply, State}.

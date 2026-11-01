%%% @doc RESPONDER for the `mcl-tenders/describe_tender_profile' procedure.
%%%
%%% Describes the profile of the realm this node serves. Only a caller the
%%% realm granted the tenders role reaches this handler: the capability
%%% declares `{callers, role}' and the call must be sealed (T2), and macula's
%%% link refuses everyone else before the handler runs. The caller, the node id
%%% that signed the call, is recorded as `described_by'.
%%%
%%% Payload: `cpv_codes', `countries', `keywords', `exclusions' (each a list
%%% of text, optional) and `description' (text, optional); the limits are
%%% describe_tender_profile_v1's. Replies `#{}' once the event is stored, or
%%% `#{reason => Why}' naming the rule that refused it (README, "Procedures").
%%% @end
-module(describe_tender_profile_responder).
-behaviour(macula_response).

-export([init/1, handle_request/2, command/2]).

init(_Args) -> {ok, []}.

-spec handle_request(map(), term()) -> {reply, map(), term()}.
handle_request(Payload, State) ->
    {reply, replied(dispatched(command(mcl_om:realm(), Payload))), State}.

%% @doc The command a CALL stands for, in the realm this node serves.
-spec command({ok, binary()} | {error, term()}, map()) ->
          {ok, describe_tender_profile_v1:t()} | {error, atom()}.
command({ok, Realm}, Payload) ->
    describe_tender_profile_v1:new(
      #{realm => Realm,
        described_by => mcl_om_wire:caller(Payload),
        cpv_codes => mcl_om_wire:field(cpv_codes, Payload, []),
        countries => mcl_om_wire:field(countries, Payload, []),
        keywords => mcl_om_wire:field(keywords, Payload, []),
        exclusions => mcl_om_wire:field(exclusions, Payload, []),
        description => mcl_om_wire:field(description, Payload, <<>>)});
command({error, _}, _Payload) ->
    {error, no_realm}.

dispatched({ok, Cmd}) -> maybe_describe_tender_profile:dispatch(Cmd);
dispatched({error, _} = Refused) -> Refused.

replied({ok, _Version, _Events}) -> #{};
replied({error, Reason}) when is_atom(Reason) -> #{reason => {text, atom_to_binary(Reason)}};
replied({error, _Unexpected}) -> #{reason => {text, <<"internal_error">>}}.

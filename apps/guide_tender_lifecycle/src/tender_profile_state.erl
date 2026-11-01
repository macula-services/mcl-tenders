%%% @doc State of the tender profile aggregate.
%%%
%%% status is a bit-flag integer (tender_profile_status.hrl), never an atom.
%%% No profile term is kept: the rules need only the flags (T8).
%%% @end
-module(tender_profile_state).
-behaviour(evoq_state).

-include("tender_profile_status.hrl").

-export([new/1, apply_event/2, to_map/1]).
-export([status/1, realm/1]).

-record(state, {
    realm :: binary() | undefined,
    status = 0 :: non_neg_integer()
}).

-type state() :: #state{}.
-export_type([state/0]).

-spec new(binary()) -> state().
new(Realm) ->
    #state{realm = Realm}.

-spec status(state()) -> non_neg_integer().
status(#state{status = S}) -> S.

-spec realm(state()) -> binary() | undefined.
realm(#state{realm = R}) -> R.

%% @doc Folds one event into state, matched on its event_type, which is how
%% the event also comes back on replay from the store.
-spec apply_event(state(), map()) -> state().
apply_event(S, #{event_type := <<"tender_profile_initiated_v1">>} = Ev) ->
    S#state{realm = maps:get(realm, Ev),
            status = evoq_bit_flags:set(S#state.status, ?TENDER_PROFILE_INITIATED)};
apply_event(S, #{event_type := <<"tender_profile_described_v1">>}) ->
    S#state{status = evoq_bit_flags:set(S#state.status, ?TENDER_PROFILE_DESCRIBED)};
apply_event(S, _Unknown) ->
    S.

-spec to_map(state()) -> map().
to_map(#state{realm = R, status = St}) ->
    #{realm => R, status => St}.

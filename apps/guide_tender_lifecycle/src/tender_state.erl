%%% @doc State of the tender aggregate.
%%%
%%% status is a bit-flag integer (tender_status.hrl), never an atom. No notice
%%% text is kept: the rules need only the flags, and a match draws the
%%% profile's outline (A2), so it stays out of the aggregate's crash reports.
%%% @end
-module(tender_state).
-behaviour(evoq_state).

-include("tender_status.hrl").

-export([new/1, apply_event/2, to_map/1]).
-export([status/1]).

-record(state, {
    stream :: binary(),
    status = 0 :: non_neg_integer()
}).

-type state() :: #state{}.
-export_type([state/0]).

-spec new(binary()) -> state().
new(StreamId) ->
    #state{stream = StreamId}.

-spec status(state()) -> non_neg_integer().
status(#state{status = S}) -> S.

%% @doc Folds one event into state, matched on its event_type, which is how
%% the event also comes back on replay from the store.
-spec apply_event(state(), map()) -> state().
apply_event(S, #{event_type := <<"tender_spotted_v1">>}) -> flagged(S, ?TENDER_SPOTTED);
apply_event(S, #{event_type := <<"tender_amended_v1">>}) -> flagged(S, ?TENDER_AMENDED);
apply_event(S, #{event_type := <<"tender_award_noted_v1">>}) -> flagged(S, ?TENDER_AWARD_PUBLISHED);
apply_event(S, #{event_type := <<"tender_dismissed_v1">>}) -> flagged(S, ?TENDER_DISMISSED);
apply_event(S, _Unknown) -> S.

flagged(#state{status = St} = S, Flag) ->
    S#state{status = evoq_bit_flags:set(St, Flag)}.

-spec to_map(state()) -> map().
to_map(#state{stream = Stream, status = St}) ->
    #{stream => Stream, status => St}.

%%% @doc Event `tender_bid_submitted_v1': the bid for a pursued tender went in. `submitted_by' is the caller macula
%%% verified (T13).
-module(tender_bid_submitted_v1).
-behaviour(evoq_event).

-export([event_type/0]).
-export([new/1, to_map/1]).

-record(tender_bid_submitted_v1, {
    realm :: binary(),
    tender_id :: binary(),
    submitted_by :: binary(),
    submitted_at :: integer()
}).

-opaque t() :: #tender_bid_submitted_v1{}.
-export_type([t/0]).

-spec event_type() -> binary().
event_type() -> <<"tender_bid_submitted_v1">>.

-spec new(map()) -> t().
new(#{realm := Realm, tender_id := Id, submitted_by := By} = Params) ->
    #tender_bid_submitted_v1{realm = Realm, tender_id = Id, submitted_by = By,
          submitted_at = maps:get(submitted_at, Params, erlang:system_time(millisecond))}.

-spec to_map(t()) -> map().
to_map(#tender_bid_submitted_v1{realm = Realm, tender_id = Id, submitted_by = By, submitted_at = At}) ->
    #{event_type => <<"tender_bid_submitted_v1">>, realm => Realm, tender_id => Id,
      submitted_by => By, submitted_at => At}.

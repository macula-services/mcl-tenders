%%% @doc Event `tender_declined_v1': the bid team stopped a pursuit without bidding. `declined_by' is the caller macula
%%% verified (T13).
-module(tender_declined_v1).
-behaviour(evoq_event).

-export([event_type/0]).
-export([new/1, to_map/1]).

-record(tender_declined_v1, {
    realm :: binary(),
    tender_id :: binary(),
    declined_by :: binary(),
    declined_at :: integer()
}).

-opaque t() :: #tender_declined_v1{}.
-export_type([t/0]).

-spec event_type() -> binary().
event_type() -> <<"tender_declined_v1">>.

-spec new(map()) -> t().
new(#{realm := Realm, tender_id := Id, declined_by := By} = Params) ->
    #tender_declined_v1{realm = Realm, tender_id = Id, declined_by = By,
          declined_at = maps:get(declined_at, Params, erlang:system_time(millisecond))}.

-spec to_map(t()) -> map().
to_map(#tender_declined_v1{realm = Realm, tender_id = Id, declined_by = By, declined_at = At}) ->
    #{event_type => <<"tender_declined_v1">>, realm => Realm, tender_id => Id,
      declined_by => By, declined_at => At}.

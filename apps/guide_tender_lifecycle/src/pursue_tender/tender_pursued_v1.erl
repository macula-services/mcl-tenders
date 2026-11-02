%%% @doc Event `tender_pursued_v1': the bid team went for a spotted tender. `pursued_by' is the caller macula
%%% verified (T13).
-module(tender_pursued_v1).
-behaviour(evoq_event).

-export([event_type/0]).
-export([new/1, to_map/1]).

-record(tender_pursued_v1, {
    realm :: binary(),
    tender_id :: binary(),
    pursued_by :: binary(),
    pursued_at :: integer()
}).

-opaque t() :: #tender_pursued_v1{}.
-export_type([t/0]).

-spec event_type() -> binary().
event_type() -> <<"tender_pursued_v1">>.

-spec new(map()) -> t().
new(#{realm := Realm, tender_id := Id, pursued_by := By} = Params) ->
    #tender_pursued_v1{realm = Realm, tender_id = Id, pursued_by = By,
          pursued_at = maps:get(pursued_at, Params, erlang:system_time(millisecond))}.

-spec to_map(t()) -> map().
to_map(#tender_pursued_v1{realm = Realm, tender_id = Id, pursued_by = By, pursued_at = At}) ->
    #{event_type => <<"tender_pursued_v1">>, realm => Realm, tender_id => Id,
      pursued_by => By, pursued_at => At}.

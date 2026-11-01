%%% @doc Event `tender_dismissed_v1': the bid team marked a spotted tender as
%%% not for the realm. `dismissed_by' is the caller macula verified (T13).
-module(tender_dismissed_v1).
-behaviour(evoq_event).

-export([event_type/0]).
-export([new/1, to_map/1]).

-record(tender_dismissed_v1, {
    realm :: binary(),
    tender_id :: binary(),
    dismissed_by :: binary(),
    dismissed_at :: integer()
}).

-opaque t() :: #tender_dismissed_v1{}.
-export_type([t/0]).

-spec event_type() -> binary().
event_type() -> <<"tender_dismissed_v1">>.

-spec new(map()) -> t().
new(#{realm := Realm, tender_id := Id, dismissed_by := By} = Params) ->
    #tender_dismissed_v1{realm = Realm, tender_id = Id, dismissed_by = By,
                         dismissed_at = maps:get(dismissed_at, Params, erlang:system_time(millisecond))}.

-spec to_map(t()) -> map().
to_map(#tender_dismissed_v1{realm = Realm, tender_id = Id, dismissed_by = By, dismissed_at = At}) ->
    #{event_type => <<"tender_dismissed_v1">>, realm => Realm, tender_id => Id,
      dismissed_by => By, dismissed_at => At}.

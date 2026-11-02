%%% @doc Event `tender_award_noted_v1': the award of a spotted tender was
%%% published, in the notice named by its publication number.
-module(tender_award_noted_v1).
-behaviour(evoq_event).

-export([event_type/0]).
-export([new/1, to_map/1]).

-record(tender_award_noted_v1, {
    realm :: binary(),
    tender_id :: binary(),
    publication_number :: binary(),
    published_at :: non_neg_integer(),
    noted_at :: integer()
}).

-opaque t() :: #tender_award_noted_v1{}.
-export_type([t/0]).

-spec event_type() -> binary().
event_type() -> <<"tender_award_noted_v1">>.

-spec new(map()) -> t().
new(#{realm := Realm, tender_id := Id, publication_number := Number, published_at := At} = Params) ->
    #tender_award_noted_v1{realm = Realm, tender_id = Id, publication_number = Number,
                           published_at = At,
                           noted_at = maps:get(noted_at, Params, erlang:system_time(millisecond))}.

-spec to_map(t()) -> map().
to_map(#tender_award_noted_v1{realm = Realm, tender_id = Id, publication_number = Number,
                              published_at = At, noted_at = Noted}) ->
    #{event_type => <<"tender_award_noted_v1">>, realm => Realm, tender_id => Id,
      publication_number => Number, published_at => At, noted_at => Noted}.

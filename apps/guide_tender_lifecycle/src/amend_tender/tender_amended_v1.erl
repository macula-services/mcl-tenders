%%% @doc Event `tender_amended_v1': a correction TED published reached a
%%% spotted tender. Carries the correction's publication number, deadline,
%%% value, titles and description, flat beside the dossier's own fields.
-module(tender_amended_v1).
-behaviour(evoq_event).

-export([event_type/0]).
-export([new/1, to_map/1]).

-record(tender_amended_v1, {
    realm :: binary(),
    tender_id :: binary(),
    correction :: map(),
    amended_at :: integer()
}).

-opaque t() :: #tender_amended_v1{}.
-export_type([t/0]).

-spec event_type() -> binary().
event_type() -> <<"tender_amended_v1">>.

-spec new(map()) -> t().
new(#{realm := Realm, tender_id := Id, correction := Correction} = Params) ->
    #tender_amended_v1{realm = Realm, tender_id = Id, correction = Correction,
                       amended_at = maps:get(amended_at, Params, erlang:system_time(millisecond))}.

-spec to_map(t()) -> map().
to_map(#tender_amended_v1{realm = Realm, tender_id = Id, correction = Correction, amended_at = At}) ->
    maps:merge(maps:with(amend_tender_v1:fields(), Correction),
               #{event_type => <<"tender_amended_v1">>, realm => Realm, tender_id => Id,
                 amended_at => At}).

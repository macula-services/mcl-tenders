%%% @doc Event `tender_profile_initiated_v1': the realm's tenders profile exists.
-module(tender_profile_initiated_v1).
-behaviour(evoq_event).

-export([event_type/0]).
-export([new/1, from_map/1, to_map/1]).
-export([get_realm/1, get_initiated_at/1]).

-record(tender_profile_initiated_v1, {
    realm :: binary(),
    initiated_at :: integer()
}).

-opaque t() :: #tender_profile_initiated_v1{}.
-export_type([t/0]).

-spec event_type() -> binary().
event_type() -> <<"tender_profile_initiated_v1">>.

-spec new(map()) -> t().
new(#{realm := Realm} = Params) ->
    #tender_profile_initiated_v1{
        realm = Realm,
        initiated_at = maps:get(initiated_at, Params, erlang:system_time(millisecond))
    }.

-spec from_map(map()) -> {ok, t()} | {error, term()}.
from_map(#{realm := Realm, initiated_at := At}) when is_binary(Realm), is_integer(At) ->
    {ok, #tender_profile_initiated_v1{realm = Realm, initiated_at = At}};
from_map(_) ->
    {error, invalid_tender_profile_initiated_event}.

-spec to_map(t()) -> map().
to_map(#tender_profile_initiated_v1{realm = Realm, initiated_at = At}) ->
    #{event_type => <<"tender_profile_initiated_v1">>, realm => Realm, initiated_at => At}.

-spec get_realm(t()) -> binary().
get_realm(#tender_profile_initiated_v1{realm = V}) -> V.

-spec get_initiated_at(t()) -> integer().
get_initiated_at(#tender_profile_initiated_v1{initiated_at = V}) -> V.

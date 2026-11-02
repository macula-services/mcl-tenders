%%% @doc Event `tender_profile_archived_v1': the realm no longer looks for public
%%% tenders. get_tender_profile answers archived from then on, and the sensor
%%% idles.
-module(tender_profile_archived_v1).
-behaviour(evoq_event).

-export([event_type/0]).
-export([new/1, from_map/1, to_map/1]).
-export([get_realm/1, get_archived_by/1, get_archived_at/1]).

-record(tender_profile_archived_v1, {
    realm :: binary(),
    archived_by :: binary(),
    archived_at :: integer()
}).

-opaque t() :: #tender_profile_archived_v1{}.
-export_type([t/0]).

-spec event_type() -> binary().
event_type() -> <<"tender_profile_archived_v1">>.

-spec new(map()) -> t().
new(#{realm := Realm, archived_by := By} = Params) ->
    #tender_profile_archived_v1{
        realm = Realm, archived_by = By,
        archived_at = maps:get(archived_at, Params, erlang:system_time(millisecond))
    }.

-spec from_map(map()) -> {ok, t()} | {error, term()}.
from_map(#{realm := Realm, archived_by := By, archived_at := At})
  when is_binary(Realm), is_binary(By), is_integer(At) ->
    {ok, #tender_profile_archived_v1{realm = Realm, archived_by = By, archived_at = At}};
from_map(_) ->
    {error, invalid_tender_profile_archived_event}.

-spec to_map(t()) -> map().
to_map(#tender_profile_archived_v1{realm = Realm, archived_by = By, archived_at = At}) ->
    #{event_type => <<"tender_profile_archived_v1">>, realm => Realm, archived_by => By,
      archived_at => At}.

-spec get_realm(t()) -> binary().
get_realm(#tender_profile_archived_v1{realm = V}) -> V.

-spec get_archived_by(t()) -> binary().
get_archived_by(#tender_profile_archived_v1{archived_by = V}) -> V.

-spec get_archived_at(t()) -> integer().
get_archived_at(#tender_profile_archived_v1{archived_at = V}) -> V.

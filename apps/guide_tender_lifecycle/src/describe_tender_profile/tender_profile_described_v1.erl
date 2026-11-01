%%% @doc Event `tender_profile_described_v1': what the realm now looks for in a
%%% public tender, replacing what it looked for before.
-module(tender_profile_described_v1).
-behaviour(evoq_event).

-export([event_type/0]).
-export([new/1, from_map/1, to_map/1]).
-export([get_realm/1, get_described_by/1, get_described_at/1]).

-record(tender_profile_described_v1, {
    realm :: binary(),
    described_by :: binary(),
    cpv_codes :: [binary()],
    countries :: [binary()],
    keywords :: [binary()],
    exclusions :: [binary()],
    description :: binary(),
    described_at :: integer()
}).

-opaque t() :: #tender_profile_described_v1{}.
-export_type([t/0]).

-spec event_type() -> binary().
event_type() -> <<"tender_profile_described_v1">>.

-spec new(map()) -> t().
new(#{realm := Realm, described_by := By, cpv_codes := Cpv, countries := Countries,
      keywords := Keywords, exclusions := Exclusions, description := Description} = Params) ->
    #tender_profile_described_v1{
        realm = Realm, described_by = By, cpv_codes = Cpv, countries = Countries,
        keywords = Keywords, exclusions = Exclusions, description = Description,
        described_at = maps:get(described_at, Params, erlang:system_time(millisecond))
    }.

-spec from_map(map()) -> {ok, t()} | {error, term()}.
from_map(#{realm := Realm, described_by := By, cpv_codes := Cpv, countries := Countries,
           keywords := Keywords, exclusions := Exclusions, description := Description,
           described_at := At})
  when is_binary(Realm), is_binary(By), is_list(Cpv), is_list(Countries), is_list(Keywords),
       is_list(Exclusions), is_binary(Description), is_integer(At) ->
    {ok, #tender_profile_described_v1{realm = Realm, described_by = By, cpv_codes = Cpv,
                                      countries = Countries, keywords = Keywords,
                                      exclusions = Exclusions, description = Description,
                                      described_at = At}};
from_map(_) ->
    {error, invalid_tender_profile_described_event}.

-spec to_map(t()) -> map().
to_map(#tender_profile_described_v1{realm = Realm, described_by = By, cpv_codes = Cpv,
                                    countries = Countries, keywords = Keywords,
                                    exclusions = Exclusions, description = Description,
                                    described_at = At}) ->
    #{event_type => <<"tender_profile_described_v1">>, realm => Realm, described_by => By,
      cpv_codes => Cpv, countries => Countries, keywords => Keywords, exclusions => Exclusions,
      description => Description, described_at => At}.

-spec get_realm(t()) -> binary().
get_realm(#tender_profile_described_v1{realm = V}) -> V.

-spec get_described_by(t()) -> binary().
get_described_by(#tender_profile_described_v1{described_by = V}) -> V.

-spec get_described_at(t()) -> integer().
get_described_at(#tender_profile_described_v1{described_at = V}) -> V.

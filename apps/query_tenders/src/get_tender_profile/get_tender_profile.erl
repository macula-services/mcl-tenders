%% @doc get_tender_profile: the realm's tenders profile, as last described.
%%
%% Called in process by the sensor and the admin UI, and through the sealed
%% procedure by an agent holding the tenders role. A profile initiated and not
%% yet described is the empty profile: no CPV code and no country, which the
%% sensor reads as "fetch nothing". An archived profile is not read at all:
%% `{error, archived}', and the sensor idles on it.
-module(get_tender_profile).

-export([find/1, columns/0]).

-type profile() :: #{cpv_codes := [binary()], countries := [binary()],
                     keywords := [binary()], exclusions := [binary()],
                     description := binary(), described_by := binary(),
                     described_at := non_neg_integer()}.
-export_type([profile/0]).

%% @doc The columns this desk selects, in order; a test pins them to
%% tenders_read_model_store:schema/0.
-spec columns() -> [string()].
columns() ->
    ["cpv_codes", "countries", "keywords", "exclusions", "description",
     "described_by", "described_at"].

%% @doc The profile of Realm, a 32-byte realm id.
-spec find(term()) ->
          {ok, profile()} | {error, not_found | archived | store_unavailable | invalid_realm}.
find(<<_:256>> = Realm) ->
    found(tenders_query_store:q(
            "SELECT " ++ lists:join(", ", columns() ++ ["archived_at"]) ++ " FROM tender_profiles"
            " WHERE realm = ? AND initiated_at IS NOT NULL",
            [binary:encode_hex(Realm, lowercase)]));
find(_NotARealm) ->
    {error, invalid_realm}.

found([[_Cpv, _Countries, _Keywords, _Exclusions, _Description, _By, _At, ArchivedAt] | _])
  when is_integer(ArchivedAt) ->
    {error, archived};
found([[Cpv, Countries, Keywords, Exclusions, Description, By, At, _NotArchived] | _]) ->
    {ok, #{cpv_codes => listed(Cpv), countries => listed(Countries),
           keywords => listed(Keywords), exclusions => listed(Exclusions),
           description => Description, described_by => By, described_at => At}};
found([]) -> {error, not_found};
found({error, _}) -> {error, store_unavailable}.

listed(<<>>) -> [];
listed(Lines) -> binary:split(Lines, <<"\n">>, [global]).

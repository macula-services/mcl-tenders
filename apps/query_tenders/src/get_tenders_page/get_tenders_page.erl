%% @doc get_tenders_page: the morning list, the realm's spotted tenders
%% published since a time, best first.
%%
%% Best first is the tenders that hit the most keywords, then the newest. A
%% dismissed tender is left out unless asked for. Each entry is a summary;
%% get_tender_by_id has the whole dossier.
-module(get_tenders_page).

-export([find/2, columns/0]).

-define(DEFAULT_LIMIT, 50).
-define(MAX_LIMIT, 100).
%% tender_state's TENDER_DISMISSED.
-define(DISMISSED, 8).

-type opts() :: #{since => non_neg_integer(), limit => pos_integer(), include_dismissed => 0 | 1}.
-export_type([opts/0]).

%% @doc The columns this desk selects, in order; a test pins them to
%% tenders_read_model_store:schema/0.
-spec columns() -> [string()].
columns() ->
    ["tender_id", "publication_number", "notice_type", "buyer_name", "buyer_country", "titles",
     "deadline_at", "estimated_value", "currency", "published_at", "status",
     "matched_cpv_codes", "matched_keywords"].

%% @doc One page of Realm's spotted tenders, a 32-byte realm id.
-spec find(term(), map()) ->
          {ok, #{tenders := [map()]}} | {error, invalid_realm | invalid_page | store_unavailable}.
find(<<_:256>> = Realm, Opts) when is_map(Opts) ->
    paged(checked(Opts), Realm);
find(_Realm, _Opts) ->
    {error, invalid_realm}.

checked(Opts) ->
    within(maps:get(since, Opts, 0), maps:get(limit, Opts, ?DEFAULT_LIMIT),
           maps:get(include_dismissed, Opts, 0)).

within(Since, Limit, Dismissed)
  when is_integer(Since), Since >= 0, is_integer(Limit), Limit >= 1, Limit =< ?MAX_LIMIT,
       (Dismissed =:= 0 orelse Dismissed =:= 1) ->
    {ok, Since, Limit, ?DISMISSED * (1 - Dismissed)};
within(_Since, _Limit, _Dismissed) ->
    invalid_page.

paged(invalid_page, _Realm) ->
    {error, invalid_page};
paged({ok, Since, Limit, Hidden}, Realm) ->
    found(tenders_query_store:q(
            "SELECT " ++ lists:join(", ", columns()) ++ " FROM tenders"
            " WHERE realm = ? AND spotted_at IS NOT NULL AND published_at >= ?"
            " AND (status & ?) = 0"
            " ORDER BY fit_rank DESC, published_at DESC, tender_id LIMIT ?",
            [binary:encode_hex(Realm, lowercase), Since, Hidden, Limit])).

found({error, _}) -> {error, store_unavailable};
found(Rows) -> {ok, #{tenders => [summary(Row) || Row <- Rows]}}.

summary([Id, Number, Type, Buyer, Country, Titles, Deadline, Value, Currency, Published, Status,
         Cpv, Keywords]) ->
    #{tender_id => Id, publication_number => Number, notice_type => Type, buyer_name => Buyer,
      buyer_country => Country, titles => tenders_rows:titles(Titles), deadline_at => Deadline,
      estimated_value => Value, currency => Currency, published_at => Published,
      status => Status, matched_cpv_codes => tenders_rows:listed(Cpv),
      matched_keywords => tenders_rows:listed(Keywords), ted_url => tenders_rows:ted_url(Number)}.

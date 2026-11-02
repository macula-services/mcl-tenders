%% @doc get_tender_by_id: one spotted tender's whole dossier, as the realm
%% last saw it: the notice, why it fits, the correction and award noted on
%% it, and who dismissed it and when.
-module(get_tender_by_id).

-export([find/2, columns/0]).

%% The longest tender id the dossier stores (tender_notice:valid_tender_id/1).
-define(MAX_ID_BYTES, 64).

%% @doc The columns this desk selects, in order; a test pins them to
%% tenders_read_model_store:schema/0.
-spec columns() -> [string()].
columns() ->
    ["tender_id", "publication_number", "procedure_id", "notice_type", "buyer_name",
     "buyer_country", "cpv_codes", "titles", "description", "description_lang",
     "deadline_at", "estimated_value", "currency", "published_at", "status",
     "matched_cpv_codes", "matched_keywords", "spotted_at", "corrected_by", "amended_at",
     "award_publication_number", "award_published_at", "dismissed_by", "dismissed_at"].

%% @doc The tender TenderId of Realm, a 32-byte realm id.
-spec find(term(), term()) ->
          {ok, map()} | {error, not_found | invalid_realm | invalid_tender_id | store_unavailable}.
find(<<_:256>> = Realm, TenderId)
  when is_binary(TenderId), byte_size(TenderId) > 0, byte_size(TenderId) =< ?MAX_ID_BYTES ->
    found(tenders_query_store:q(
            "SELECT " ++ lists:join(", ", columns()) ++ " FROM tenders"
            " WHERE realm = ? AND tender_id = ? AND spotted_at IS NOT NULL",
            [binary:encode_hex(Realm, lowercase), TenderId]));
find(<<_:256>>, _TenderId) ->
    {error, invalid_tender_id};
find(_Realm, _TenderId) ->
    {error, invalid_realm}.

found([Row | _]) -> {ok, dossier(Row)};
found([]) -> {error, not_found};
found({error, _}) -> {error, store_unavailable}.

dossier([Id, Number, Procedure, Type, Buyer, Country, Cpv, Titles, Description, Lang,
         Deadline, Value, Currency, Published, Status, MatchedCpv, MatchedKeywords, Spotted,
         CorrectedBy, AmendedAt, AwardNumber, AwardAt, DismissedBy, DismissedAt]) ->
    #{tender_id => Id, publication_number => Number, procedure_id => Procedure,
      notice_type => Type, buyer_name => Buyer, buyer_country => Country,
      cpv_codes => tenders_rows:listed(Cpv), titles => tenders_rows:titles(Titles),
      description => Description, description_lang => Lang, deadline_at => Deadline,
      estimated_value => Value, currency => Currency, published_at => Published,
      status => Status, matched_cpv_codes => tenders_rows:listed(MatchedCpv),
      matched_keywords => tenders_rows:listed(MatchedKeywords), spotted_at => Spotted,
      corrected_by => CorrectedBy, amended_at => AmendedAt,
      award_publication_number => AwardNumber, award_published_at => AwardAt,
      dismissed_by => DismissedBy, dismissed_at => DismissedAt,
      ted_url => tenders_rows:ted_url(Number)}.

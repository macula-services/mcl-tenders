%% @doc Projects tender_spotted_v1 into the tenders table: the dossier's row,
%% with the notice, why it fit, and its rank on the morning list (the number
%% of keywords it hit).
%%
%% One upsert, so a replay is the same write again. A correction projected
%% before this event already holds the newest deadline, value, titles and
%% description; where it gave one, the spotted notice's does not replace it.
-module(tender_spotted_v1_to_tenders).

-behaviour(evoq_event_handler).

-export([interested_in/0, init/1, handle_event/4, replay_policy/0]).

%% tender_state's TENDER_SPOTTED; a test pins it to tender_status.hrl.
-define(SPOTTED, 1).

interested_in() -> [<<"tender_spotted_v1">>].

replay_policy() -> deliver.

init(_Config) -> {ok, #{}}.


handle_event(_EventType, Event, _Metadata, State) ->
    D = maps:get(data, Event, Event),
    stored(tenders_read_model_store:exec(
             "INSERT INTO tenders (realm, tender_id, status, publication_number, procedure_id,"
             " notice_type, buyer_name, buyer_country, cpv_codes, deadline_at, estimated_value,"
             " currency, titles, description, description_lang, published_at, matched_cpv_codes,"
             " matched_keywords, fit_rank, spotted_at)"
             " VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)"
             " ON CONFLICT(realm, tender_id) DO UPDATE SET status = tenders.status | excluded.status,"
             " publication_number = excluded.publication_number,"
             " procedure_id = excluded.procedure_id, notice_type = excluded.notice_type,"
             " buyer_name = excluded.buyer_name, buyer_country = excluded.buyer_country,"
             " cpv_codes = excluded.cpv_codes,"
             " deadline_at = " ++ kept("deadline_at", "0") ++ ","
             " estimated_value = " ++ kept("estimated_value", "''") ++ ","
             " currency = " ++ kept("currency", "''") ++ ","
             " titles = " ++ kept("titles", "'{}'") ++ ","
             " description = " ++ kept("description", "''") ++ ","
             " description_lang = " ++ kept("description_lang", "''") ++ ","
             " published_at = excluded.published_at, matched_cpv_codes = excluded.matched_cpv_codes,"
             " matched_keywords = excluded.matched_keywords, fit_rank = excluded.fit_rank,"
             " spotted_at = excluded.spotted_at",
             [hex(maps:get(realm, D)), maps:get(tender_id, D), ?SPOTTED,
              maps:get(publication_number, D), maps:get(procedure_id, D), maps:get(notice_type, D),
              maps:get(buyer_name, D), maps:get(buyer_country, D), lines(maps:get(cpv_codes, D)),
              maps:get(deadline_at, D), maps:get(estimated_value, D), maps:get(currency, D),
              json(maps:get(titles, D)), maps:get(description, D), maps:get(description_lang, D),
              maps:get(published_at, D), lines(maps:get(matched_cpv_codes, D)),
              lines(maps:get(matched_keywords, D)), length(maps:get(matched_keywords, D)),
              maps:get(spotted_at, D)]), State).

%% A column a correction set stays; otherwise the spotted notice's value.
kept(Column, Empty) ->
    "CASE WHEN tenders.amended_version >= 0 AND tenders." ++ Column ++ " <> " ++ Empty ++
        " THEN tenders." ++ Column ++ " ELSE excluded." ++ Column ++ " END".

stored(ok, State) -> {ok, State};
stored({error, Reason}, _State) -> {error, {store_error, Reason}}.

lines(List) -> iolist_to_binary(lists:join(<<"\n">>, List)).

json(Titles) -> iolist_to_binary(json:encode(Titles)).

hex(Bin) -> binary:encode_hex(Bin, lowercase).

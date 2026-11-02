%% @doc Projects tender_amended_v1 into the tenders table: the newest
%% correction's deadline, value, titles and description replace the row's,
%% each only where the correction gave one.
%%
%% One upsert carrying the event's version: an older correction, or a replay
%% of this one, changes nothing it should not.
-module(tender_amended_v1_to_tenders).

-behaviour(evoq_event_handler).

-export([interested_in/0, init/1, handle_event/4, replay_policy/0]).

%% tender_state's TENDER_AMENDED; a test pins it to tender_status.hrl.
-define(AMENDED, 2).

interested_in() -> [<<"tender_amended_v1">>].

replay_policy() -> deliver.

init(_Config) -> {ok, #{}}.

handle_event(_EventType, Event, _Metadata, State) ->
    D = maps:get(data, Event, Event),
    stored(tenders_read_model_store:exec(
             "INSERT INTO tenders (realm, tender_id, status, corrected_by, deadline_at,"
             " estimated_value, currency, titles, description, description_lang, amended_at,"
             " amended_version)"
             " VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)"
             " ON CONFLICT(realm, tender_id) DO UPDATE SET status = tenders.status | excluded.status,"
             " corrected_by = excluded.corrected_by,"
             " deadline_at = " ++ given("deadline_at", "0") ++ ","
             " estimated_value = " ++ given("estimated_value", "''") ++ ","
             " currency = " ++ given("currency", "''") ++ ","
             " titles = " ++ given("titles", "'{}'") ++ ","
             " description = " ++ given("description", "''") ++ ","
             " description_lang = " ++ given("description_lang", "''") ++ ","
             " amended_at = excluded.amended_at, amended_version = excluded.amended_version"
             " WHERE excluded.amended_version > tenders.amended_version",
             [hex(maps:get(realm, D)), maps:get(tender_id, D), ?AMENDED,
              maps:get(publication_number, D), maps:get(deadline_at, D),
              maps:get(estimated_value, D), maps:get(currency, D), json(maps:get(titles, D)),
              maps:get(description, D), maps:get(description_lang, D), maps:get(amended_at, D),
              maps:get(version, Event, 0)]), State).

%% The correction's value where it gave one; the row's otherwise.
given(Column, Empty) ->
    "CASE WHEN excluded." ++ Column ++ " <> " ++ Empty ++
        " THEN excluded." ++ Column ++ " ELSE tenders." ++ Column ++ " END".

stored(ok, State) -> {ok, State};
stored({error, Reason}, _State) -> {error, {store_error, Reason}}.

json(Titles) -> iolist_to_binary(json:encode(Titles)).

hex(Bin) -> binary:encode_hex(Bin, lowercase).

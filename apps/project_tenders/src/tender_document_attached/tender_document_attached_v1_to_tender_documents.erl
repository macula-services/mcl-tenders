%% @doc Projects tender_document_attached_v1 into the tender_documents table:
%% one row per document of a tender, keyed by its SHA-256, with its name,
%% where it lies, who attached it and when. One upsert; attaching the same
%% digest again replaces the name and the place, and a replay writes the same
%% again. The name and the place are the bid team's and never reach a log (T8).
-module(tender_document_attached_v1_to_tender_documents).

-behaviour(evoq_event_handler).

-export([interested_in/0, init/1, handle_event/4, replay_policy/0]).

interested_in() -> [<<"tender_document_attached_v1">>].

replay_policy() -> deliver.

init(_Config) -> {ok, #{}}.

handle_event(_EventType, Event, _Metadata, State) ->
    D = maps:get(data, Event, Event),
    stored(tenders_read_model_store:exec(
             "INSERT INTO tender_documents"
             " (realm, tender_id, sha256, name, location, attached_by, attached_at)"
             " VALUES (?, ?, ?, ?, ?, ?, ?)"
             " ON CONFLICT(realm, tender_id, sha256) DO UPDATE SET name = excluded.name,"
             " location = excluded.location, attached_by = excluded.attached_by,"
             " attached_at = excluded.attached_at",
             [hex(maps:get(realm, D)), maps:get(tender_id, D), maps:get(sha256, D),
              maps:get(name, D), maps:get(location, D), hex(maps:get(attached_by, D)),
              maps:get(attached_at, D)]), State).

stored(ok, State) -> {ok, State};
stored({error, Reason}, _State) -> {error, {store_error, Reason}}.

hex(Bin) -> binary:encode_hex(Bin, lowercase).

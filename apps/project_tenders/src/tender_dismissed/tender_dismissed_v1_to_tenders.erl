%% @doc Projects tender_dismissed_v1 into the tenders table: who said "not for
%% us", and when. One upsert; a replay writes the same again.
-module(tender_dismissed_v1_to_tenders).

-behaviour(evoq_event_handler).

-export([interested_in/0, init/1, handle_event/4, replay_policy/0]).

%% tender_state's TENDER_DISMISSED; a test pins it to tender_status.hrl.
-define(DISMISSED, 8).

interested_in() -> [<<"tender_dismissed_v1">>].

replay_policy() -> deliver.

init(_Config) -> {ok, #{}}.

handle_event(_EventType, Event, _Metadata, State) ->
    D = maps:get(data, Event, Event),
    stored(tenders_read_model_store:exec(
             "INSERT INTO tenders (realm, tender_id, status, dismissed_by, dismissed_at)"
             " VALUES (?, ?, ?, ?, ?)"
             " ON CONFLICT(realm, tender_id) DO UPDATE SET status = tenders.status | excluded.status,"
             " dismissed_by = excluded.dismissed_by, dismissed_at = excluded.dismissed_at",
             [hex(maps:get(realm, D)), maps:get(tender_id, D), ?DISMISSED,
              hex(maps:get(dismissed_by, D)), maps:get(dismissed_at, D)]), State).

stored(ok, State) -> {ok, State};
stored({error, Reason}, _State) -> {error, {store_error, Reason}}.

hex(Bin) -> binary:encode_hex(Bin, lowercase).

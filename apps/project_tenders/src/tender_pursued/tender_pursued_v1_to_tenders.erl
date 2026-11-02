%% @doc Projects tender_pursued_v1 into the tenders table: who went for the tender, and when. One
%% upsert; a replay writes the same again.
-module(tender_pursued_v1_to_tenders).

-behaviour(evoq_event_handler).

-export([interested_in/0, init/1, handle_event/4, replay_policy/0]).

%% tender_state's TENDER_PURSUED; a test pins it to tender_status.hrl.
-define(FLAG, 16).

interested_in() -> [<<"tender_pursued_v1">>].

replay_policy() -> deliver.

init(_Config) -> {ok, #{}}.

handle_event(_EventType, Event, _Metadata, State) ->
    D = maps:get(data, Event, Event),
    stored(tenders_read_model_store:exec(
             "INSERT INTO tenders (realm, tender_id, status, pursued_by, pursued_at)"
             " VALUES (?, ?, ?, ?, ?)"
             " ON CONFLICT(realm, tender_id) DO UPDATE SET status = tenders.status | excluded.status,"
             " pursued_by = excluded.pursued_by, pursued_at = excluded.pursued_at",
             [hex(maps:get(realm, D)), maps:get(tender_id, D), ?FLAG,
              hex(maps:get(pursued_by, D)), maps:get(pursued_at, D)]), State).

stored(ok, State) -> {ok, State};
stored({error, Reason}, _State) -> {error, {store_error, Reason}}.

hex(Bin) -> binary:encode_hex(Bin, lowercase).

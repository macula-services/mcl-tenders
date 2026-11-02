%% @doc Projects tender_declined_v1 into the tenders table: who stopped the pursuit without a bid, and when. One
%% upsert; a replay writes the same again.
-module(tender_declined_v1_to_tenders).

-behaviour(evoq_event_handler).

-export([interested_in/0, init/1, handle_event/4, replay_policy/0]).

%% tender_state's TENDER_DECLINED; a test pins it to tender_status.hrl.
-define(FLAG, 32).

interested_in() -> [<<"tender_declined_v1">>].

replay_policy() -> deliver.

init(_Config) -> {ok, #{}}.

handle_event(_EventType, Event, _Metadata, State) ->
    D = maps:get(data, Event, Event),
    stored(tenders_read_model_store:exec(
             "INSERT INTO tenders (realm, tender_id, status, declined_by, declined_at)"
             " VALUES (?, ?, ?, ?, ?)"
             " ON CONFLICT(realm, tender_id) DO UPDATE SET status = tenders.status | excluded.status,"
             " declined_by = excluded.declined_by, declined_at = excluded.declined_at",
             [hex(maps:get(realm, D)), maps:get(tender_id, D), ?FLAG,
              hex(maps:get(declined_by, D)), maps:get(declined_at, D)]), State).

stored(ok, State) -> {ok, State};
stored({error, Reason}, _State) -> {error, {store_error, Reason}}.

hex(Bin) -> binary:encode_hex(Bin, lowercase).

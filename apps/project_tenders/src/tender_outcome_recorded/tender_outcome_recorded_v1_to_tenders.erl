%% @doc Projects tender_outcome_recorded_v1 into the tenders table: won or
%% lost, who recorded it, and when. One upsert; a replay writes the same again.
-module(tender_outcome_recorded_v1_to_tenders).

-behaviour(evoq_event_handler).

-export([interested_in/0, init/1, handle_event/4, replay_policy/0]).

%% tender_state's TENDER_WON and TENDER_LOST; a test pins them to
%% tender_status.hrl.
-define(WON, 128).
-define(LOST, 256).

interested_in() -> [<<"tender_outcome_recorded_v1">>].

replay_policy() -> deliver.

init(_Config) -> {ok, #{}}.

handle_event(_EventType, Event, _Metadata, State) ->
    D = maps:get(data, Event, Event),
    Outcome = maps:get(outcome, D),
    stored(tenders_read_model_store:exec(
             "INSERT INTO tenders (realm, tender_id, status, outcome, outcome_by, outcome_at)"
             " VALUES (?, ?, ?, ?, ?, ?)"
             " ON CONFLICT(realm, tender_id) DO UPDATE SET status = tenders.status | excluded.status,"
             " outcome = excluded.outcome, outcome_by = excluded.outcome_by,"
             " outcome_at = excluded.outcome_at",
             [hex(maps:get(realm, D)), maps:get(tender_id, D), flag(Outcome), Outcome,
              hex(maps:get(recorded_by, D)), maps:get(recorded_at, D)]), State).

flag(<<"won">>) -> ?WON;
flag(<<"lost">>) -> ?LOST.

stored(ok, State) -> {ok, State};
stored({error, Reason}, _State) -> {error, {store_error, Reason}}.

hex(Bin) -> binary:encode_hex(Bin, lowercase).

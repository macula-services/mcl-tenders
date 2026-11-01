%% @doc Projects tender_award_noted_v1 into the tenders table: which notice
%% published the award, and when. One upsert; a replay writes the same again.
-module(tender_award_noted_v1_to_tenders).

-behaviour(evoq_event_handler).

-export([interested_in/0, init/1, handle_event/4, replay_policy/0]).

%% tender_state's TENDER_AWARD_PUBLISHED; a test pins it to tender_status.hrl.
-define(AWARD_PUBLISHED, 4).

interested_in() -> [<<"tender_award_noted_v1">>].

replay_policy() -> deliver.

init(_Config) -> {ok, #{}}.

handle_event(_EventType, Event, _Metadata, State) ->
    D = maps:get(data, Event, Event),
    stored(tenders_read_model_store:exec(
             "INSERT INTO tenders (realm, tender_id, status, award_publication_number,"
             " award_published_at) VALUES (?, ?, ?, ?, ?)"
             " ON CONFLICT(realm, tender_id) DO UPDATE SET status = tenders.status | excluded.status,"
             " award_publication_number = excluded.award_publication_number,"
             " award_published_at = excluded.award_published_at",
             [hex(maps:get(realm, D)), maps:get(tender_id, D), ?AWARD_PUBLISHED,
              maps:get(publication_number, D), maps:get(published_at, D)]), State).

stored(ok, State) -> {ok, State};
stored({error, Reason}, _State) -> {error, {store_error, Reason}}.

hex(Bin) -> binary:encode_hex(Bin, lowercase).

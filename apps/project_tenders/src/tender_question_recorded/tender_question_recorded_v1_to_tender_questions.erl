%% @doc Projects tender_question_recorded_v1 into the tender_questions table:
%% one row per question on a tender, keyed by its question_id (the SHA-256 of
%% its text), with who recorded it first and when. The same question recorded
%% again changes nothing, so the first caller stays the one who asked it, and a
%% replay, in stream order, writes the same row again. The question is the bid team's and never reaches a log (T8).
-module(tender_question_recorded_v1_to_tender_questions).

-behaviour(evoq_event_handler).

-export([interested_in/0, init/1, handle_event/4, replay_policy/0]).

interested_in() -> [<<"tender_question_recorded_v1">>].

replay_policy() -> deliver.

init(_Config) -> {ok, #{}}.

handle_event(_EventType, Event, _Metadata, State) ->
    D = maps:get(data, Event, Event),
    stored(tenders_read_model_store:exec(
             "INSERT INTO tender_questions"
             " (realm, tender_id, question_id, question, recorded_by, recorded_at)"
             " VALUES (?, ?, ?, ?, ?, ?)"
             " ON CONFLICT(realm, tender_id, question_id) DO NOTHING",
             [hex(maps:get(realm, D)), maps:get(tender_id, D), maps:get(question_id, D),
              maps:get(question, D), hex(maps:get(recorded_by, D)), maps:get(recorded_at, D)]),
           State).

stored(ok, State) -> {ok, State};
stored({error, Reason}, _State) -> {error, {store_error, Reason}}.

hex(Bin) -> binary:encode_hex(Bin, lowercase).

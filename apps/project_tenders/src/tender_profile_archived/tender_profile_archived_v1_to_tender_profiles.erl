%% @doc Projects tender_profile_archived_v1 into the tender_profiles table.
%% Records that the realm no longer looks, when, and who said so.
%%
%% One upsert setting only this event's columns (tenders_read_model_store says
%% why), so a replay is the same write again and order across events does not
%% matter.
-module(tender_profile_archived_v1_to_tender_profiles).

-behaviour(evoq_event_handler).

-export([interested_in/0, init/1, handle_event/4, replay_policy/0]).

interested_in() -> [<<"tender_profile_archived_v1">>].

replay_policy() -> deliver.

init(_Config) -> {ok, #{}}.

handle_event(_EventType, Event, _Metadata, State) ->
    Data = maps:get(data, Event, Event),
    stored(tenders_read_model_store:exec(
             "INSERT INTO tender_profiles (realm, archived_at, archived_by) VALUES (?, ?, ?)"
             " ON CONFLICT(realm) DO UPDATE SET archived_at = excluded.archived_at,"
             " archived_by = excluded.archived_by",
             [hex(maps:get(realm, Data)), maps:get(archived_at, Data),
              hex(maps:get(archived_by, Data))]), State).

stored(ok, State) -> {ok, State};
stored({error, Reason}, _State) -> {error, {store_error, Reason}}.

hex(Bin) -> binary:encode_hex(Bin, lowercase).

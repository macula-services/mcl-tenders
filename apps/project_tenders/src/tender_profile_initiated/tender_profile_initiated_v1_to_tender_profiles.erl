%% @doc Projects tender_profile_initiated_v1 into the tender_profiles table.
%% Records that the realm's profile exists, and when.
%%
%% One upsert setting only this event's columns (tenders_read_model_store says
%% why), so a replay is the same write again and order across events does not
%% matter.
-module(tender_profile_initiated_v1_to_tender_profiles).

-behaviour(evoq_event_handler).

-export([interested_in/0, init/1, handle_event/4, replay_policy/0]).

interested_in() -> [<<"tender_profile_initiated_v1">>].

replay_policy() -> deliver.

init(_Config) -> {ok, #{}}.

handle_event(_EventType, Event, _Metadata, State) ->
    Data = maps:get(data, Event, Event),
    stored(tenders_read_model_store:exec(
             "INSERT INTO tender_profiles (realm, initiated_at) VALUES (?, ?)"
             " ON CONFLICT(realm) DO UPDATE SET initiated_at = excluded.initiated_at",
             [hex(maps:get(realm, Data)), maps:get(initiated_at, Data)]), State).

stored(ok, State) -> {ok, State};
stored({error, Reason}, _State) -> {error, {store_error, Reason}}.

hex(Bin) -> binary:encode_hex(Bin, lowercase).

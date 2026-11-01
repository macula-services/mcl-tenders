%% @doc Projects tender_profile_described_v1 into the tender_profiles table.
%% Writes the description, unless a later one is already there.
%%
%% One upsert setting only this event's columns (tenders_read_model_store says
%% why), so a replay is the same write again and order across events does not
%% matter.
-module(tender_profile_described_v1_to_tender_profiles).

-behaviour(evoq_event_handler).

-export([interested_in/0, init/1, handle_event/4, replay_policy/0]).

interested_in() -> [<<"tender_profile_described_v1">>].

replay_policy() -> deliver.

init(_Config) -> {ok, #{}}.

handle_event(_EventType, Event, _Metadata, State) ->
    Data = maps:get(data, Event, Event),
    stored(tenders_read_model_store:exec(
             "INSERT INTO tender_profiles (realm, cpv_codes, countries, keywords, exclusions,"
             " description, described_by, described_at, described_version)"
             " VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)"
             " ON CONFLICT(realm) DO UPDATE SET cpv_codes = excluded.cpv_codes,"
             " countries = excluded.countries, keywords = excluded.keywords,"
             " exclusions = excluded.exclusions, description = excluded.description,"
             " described_by = excluded.described_by, described_at = excluded.described_at,"
             " described_version = excluded.described_version"
             " WHERE excluded.described_version > tender_profiles.described_version",
             [hex(maps:get(realm, Data)), lines(maps:get(cpv_codes, Data)),
              lines(maps:get(countries, Data)), lines(maps:get(keywords, Data)),
              lines(maps:get(exclusions, Data)), maps:get(description, Data),
              hex(maps:get(described_by, Data)), maps:get(described_at, Data),
              maps:get(version, Event, 0)]), State).

stored(ok, State) -> {ok, State};
stored({error, Reason}, _State) -> {error, {store_error, Reason}}.

lines(List) -> iolist_to_binary(lists:join(<<"\n">>, List)).

hex(Bin) -> binary:encode_hex(Bin, lowercase).

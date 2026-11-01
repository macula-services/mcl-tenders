%%% @doc The profile through the whole released pipeline, end to end with no
%%% mesh: the boot's initiation, a description dispatched by the responder as
%%% a role holder's call arrives, the projection, and the profile read back in
%%% process as the sensor and the admin UI read it.
-module(mcl_tenders_read_side_tests).

-include_lib("eunit/include/eunit.hrl").

-define(MEMBER, <<16#a1:256>>).

read_side_test_() ->
    {setup, fun() -> mcl_tenders_pipeline:start("mcl_tenders_read_side_tests") end,
     fun mcl_tenders_pipeline:stop/1,
     [{timeout, 60, fun no_profile_before_the_first_boot/0},
      {timeout, 60, fun the_boot_initiates_the_empty_profile_once/0},
      {timeout, 60, fun a_description_is_read_back_in_process/0},
      {timeout, 60, fun a_new_description_replaces_the_old/0},
      {timeout, 60, fun a_refused_description_changes_nothing/0},
      {timeout, 60, fun a_replayed_older_description_changes_nothing/0},
      {timeout, 60, fun the_read_needs_a_realm_id/0},
      {timeout, 60, fun the_read_model_is_a_write_ahead_log/0}]}.

realm() -> mcl_tenders_pipeline:realm().

profile() -> get_tender_profile:find(realm()).

described(Args) -> mcl_tenders_pipeline:call(<<"describe_tender_profile">>, Args, ?MEMBER).

field(Field) -> fun() -> field(Field, profile()) end.

field(Field, {ok, Profile}) -> maps:get(Field, Profile);
field(_Field, {error, Reason}) -> Reason.

no_profile_before_the_first_boot() ->
    ?assertEqual({error, not_found}, profile()),
    %% And a description before it is refused by the aggregate.
    ?assertEqual({<<"describe_tender_profile">>, #{<<"reason">> => {text, <<"not_initiated">>}}},
                 described(#{cpv_codes => [{text, <<"72000000">>}]})).

%% mcl_tenders_service:start/1 calls this on every boot.
the_boot_initiates_the_empty_profile_once() ->
    ?assertEqual(ok, maybe_initiate_tender_profile:for_realm(realm())),
    ?assertEqual(ok, maybe_initiate_tender_profile:for_realm(realm())),
    mcl_tenders_pipeline:eventually(fun profile/0,
                                    {ok, #{cpv_codes => [], countries => [], keywords => [],
                                           exclusions => [], description => <<>>,
                                           described_by => <<>>, described_at => 0}}).

a_description_is_read_back_in_process() ->
    ?assertEqual({<<"describe_tender_profile">>, #{}},
                 described(#{cpv_codes => [{text, <<"72000000">>}, {text, <<"48000000">>}],
                             countries => [{text, <<"BEL">>}, {text, <<"NLD">>}],
                             keywords => [{text, <<"event store">>}],
                             exclusions => [{text, <<"catering">>}],
                             description => {text, <<"We build event stores.\nIn Erlang.">>}})),
    mcl_tenders_pipeline:eventually(field(cpv_codes), [<<"48000000">>, <<"72000000">>]),
    {ok, P} = profile(),
    ?assertMatch(#{countries := [<<"BEL">>, <<"NLD">>], keywords := [<<"event store">>],
                   exclusions := [<<"catering">>],
                   description := <<"We build event stores.\nIn Erlang.">>}, P),
    ?assertEqual(binary:encode_hex(?MEMBER, lowercase), maps:get(described_by, P)),
    ?assert(maps:get(described_at, P) > 0).

a_new_description_replaces_the_old() ->
    ?assertEqual({<<"describe_tender_profile">>, #{}},
                 described(#{countries => [{text, <<"LUX">>}]})),
    mcl_tenders_pipeline:eventually(field(countries), [<<"LUX">>]),
    ?assertMatch({ok, #{cpv_codes := [], keywords := [], description := <<>>}}, profile()).

a_refused_description_changes_nothing() ->
    ?assertEqual({<<"describe_tender_profile">>, #{<<"reason">> => {text, <<"invalid_cpv_codes">>}}},
                 described(#{cpv_codes => [{text, <<"not-a-code">>}]})),
    ?assertEqual({<<"describe_tender_profile">>, #{<<"reason">> => {text, <<"no_caller">>}}},
                 mcl_tenders_pipeline:call(<<"describe_tender_profile">>, #{}, undefined)),
    ?assertEqual([<<"LUX">>], field(countries, profile())).

%% An older description delivered after a newer one (a replay, or delivery
%% out of order) does not bring the old profile back.
a_replayed_older_description_changes_nothing() ->
    Old = #{data => #{realm => realm(), described_by => ?MEMBER, cpv_codes => [<<"11111111">>],
                      countries => [], keywords => [], exclusions => [], description => <<>>,
                      described_at => 1},
            version => 0},
    {ok, _} = tender_profile_described_v1_to_tender_profiles:handle_event(
                <<"tender_profile_described_v1">>, Old, #{}, #{}),
    ?assertEqual([<<"LUX">>], field(countries, profile())).

the_read_needs_a_realm_id() ->
    ?assertEqual({error, invalid_realm}, get_tender_profile:find(<<"io.example">>)),
    ?assertEqual({error, not_found}, get_tender_profile:find(<<16#99:256>>)).

%% WAL, so the reader and the writer do not lock each other out, and both wait
%% a moment for a lock instead of answering store_unavailable at once.
the_read_model_is_a_write_ahead_log() ->
    ?assertEqual([[<<"wal">>]], tenders_query_store:q("PRAGMA journal_mode", [])),
    ?assertEqual([[2000]], tenders_query_store:q("PRAGMA busy_timeout", [])),
    ?assertEqual([[2000]], tenders_read_model_store:q("PRAGMA busy_timeout", [])).

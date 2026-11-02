%%% @doc The tender dossier through the whole released pipeline, with no mesh:
%%% a reported notice spotted against the realm's profile, the morning list and
%%% the dossier read back, a correction, the award, a dismissal by a role
%%% holder's call, a pursuit from bid to outcome and one declined, and the read
%%% model's shape held to what the desks select.
-module(mcl_tenders_dossier_tests).

-include_lib("eunit/include/eunit.hrl").
-include_lib("guide_tender_lifecycle/src/tender_status.hrl").

-import(tender_notice_fixture, [fact/0, fact/1]).

-define(MEMBER, <<16#a1:256>>).
-define(TENDER, <<"85e562c1-17d1-4192-a543-082edb9b62ab">>).

dossier_test_() ->
    {setup, fun() -> mcl_tenders_pipeline:start("mcl_tenders_dossier_tests") end,
     fun mcl_tenders_pipeline:stop/1,
     [{timeout, 60, fun nothing_is_spotted_without_a_profile/0},
      {timeout, 60, fun a_fitting_notice_reaches_the_morning_list/0},
      {timeout, 60, fun the_dossier_is_read_whole_by_id/0},
      {timeout, 60, fun a_notice_that_does_not_fit_leaves_no_dossier/0},
      {timeout, 60, fun a_repeated_notice_is_spotted_once/0},
      {timeout, 60, fun a_correction_replaces_what_it_gives/0},
      {timeout, 60, fun the_award_is_noted_on_the_dossier/0},
      {timeout, 60, fun a_dismissal_hides_the_tender_and_names_the_caller/0},
      {timeout, 60, fun a_pursuit_runs_from_bid_to_outcome_and_names_each_caller/0},
      {timeout, 60, fun a_declined_pursuit_reads_declined/0},
      {timeout, 60, fun a_lost_pursuit_reads_lost/0},
      {timeout, 60, fun the_list_is_best_first_and_bounded/0},
      {timeout, 60, fun a_correction_projected_before_its_spot_is_kept/0},
      {timeout, 60, fun a_correction_of_a_tender_never_spotted_is_not_listed/0},
      {timeout, 60, fun the_queries_check_what_they_are_asked/0}]}.

realm() -> mcl_tenders_pipeline:realm().

page(Opts) ->
    {ok, #{tenders := Ts}} = get_tenders_page:find(realm(), Opts),
    Ts.

ids(Opts) -> [maps:get(tender_id, T) || T <- page(Opts)].

by_id(Id) -> get_tender_by_id:find(realm(), Id).

field(Id, Field) -> fun() -> field_of(by_id(Id), Field) end.

field_of({ok, D}, Field) -> maps:get(Field, D);
field_of({error, Why}, _Field) -> Why.

described(Args) ->
    {_, #{}} = mcl_tenders_pipeline:call(<<"describe_tender_profile">>, Args, ?MEMBER).

nothing_is_spotted_without_a_profile() ->
    ?assertEqual({skipped, no_profile}, mcl_tenders_pipeline:reported(fact())),
    ok = maybe_initiate_tender_profile:for_realm(realm()),
    described(#{cpv_codes => [{text, <<"72000000">>}],
                countries => [{text, <<"BEL">>}, {text, <<"NLD">>}],
                keywords => [{text, <<"erlang">>}, {text, <<"openbare">>}]}),
    mcl_tenders_pipeline:eventually(
      fun() -> element(1, get_tender_profile:find(realm())) =:= ok andalso
                   maps:get(keywords, element(2, get_tender_profile:find(realm()))) end,
      [<<"erlang">>, <<"openbare">>]).

a_fitting_notice_reaches_the_morning_list() ->
    ?assertEqual({spot_tender, ok}, mcl_tenders_pipeline:reported(fact())),
    mcl_tenders_pipeline:eventually(fun() -> ids(#{}) end, [?TENDER]),
    [T] = page(#{}),
    ?assertMatch(#{publication_number := <<"745687-2026">>, notice_type := <<"contract_notice">>,
                   buyer_name := <<"Gemeente Voorbeeld">>, buyer_country := <<"NLD">>,
                   deadline_at := 1795000000000, estimated_value := <<"1257827.41">>,
                   currency := <<"EUR">>, published_at := 1793000000000,
                   status := ?TENDER_SPOTTED, matched_cpv_codes := [<<"72000000">>],
                   ted_url := <<"https://ted.europa.eu/en/notice/-/detail/745687-2026">>}, T),
    ?assertEqual(lists:sort([<<"erlang">>, <<"openbare">>]), lists:sort(maps:get(matched_keywords, T))),
    ?assertEqual([#{lang => <<"eng">>, title => <<"Application for public order">>},
                  #{lang => <<"nld">>, title => <<"Applicatie voor openbare orde">>}],
                 maps:get(titles, T)),
    %% A summary: the dossier's text stays behind get_tender_by_id.
    ?assertNot(maps:is_key(description, T)).

the_dossier_is_read_whole_by_id() ->
    {ok, D} = by_id(?TENDER),
    ?assertMatch(#{procedure_id := ?TENDER, cpv_codes := [<<"48000000">>, <<"72260000">>],
                   description := <<"De gemeente zoekt een Erlang-applicatie.">>,
                   description_lang := <<"nld">>, corrected_by := <<>>, amended_at := 0,
                   award_publication_number := <<>>, award_published_at := 0,
                   dismissed_by := <<>>, dismissed_at := 0, spotted_at := At} when At > 0, D),
    ?assertEqual(lists:sort(get_tender_by_id:columns() ++ ["ted_url"]),
                 lists:sort([atom_to_list(K) || K <- maps:keys(D)])).

a_notice_that_does_not_fit_leaves_no_dossier() ->
    ?assertEqual({skipped, {no_fit, country}},
                 mcl_tenders_pipeline:reported(fact(#{procedure_id => <<"other-1">>,
                                                      buyer_country => <<"FRA">>}))),
    ?assertEqual({skipped, {no_fit, keyword}},
                 mcl_tenders_pipeline:reported(fact(#{procedure_id => <<"other-2">>,
                                                      titles => #{<<"eng">> => <<"Catering">>},
                                                      description => <<"Lunch">>}))),
    ?assertEqual({error, not_found}, by_id(<<"other-1">>)),
    ?assertEqual({error, not_found}, by_id(<<"other-2">>)).

a_repeated_notice_is_spotted_once() ->
    ?assertEqual({spot_tender, already_spotted}, mcl_tenders_pipeline:reported(fact())).

a_correction_replaces_what_it_gives() ->
    ?assertEqual({amend_tender, ok},
                 mcl_tenders_pipeline:reported(fact(#{notice_type => <<"correction">>,
                                                      publication_number => <<"750001-2026">>,
                                                      deadline_at => 1796000000000,
                                                      estimated_value => <<>>,
                                                      titles => #{}, description => <<>>}))),
    mcl_tenders_pipeline:eventually(field(?TENDER, deadline_at), 1796000000000),
    {ok, D} = by_id(?TENDER),
    ?assertMatch(#{corrected_by := <<"750001-2026">>, estimated_value := <<"1257827.41">>,
                   description := <<"De gemeente zoekt een Erlang-applicatie.">>,
                   status := ?TENDER_SPOTTED bor ?TENDER_AMENDED, amended_at := At} when At > 0, D),
    ?assertEqual(2, length(maps:get(titles, D))).

the_award_is_noted_on_the_dossier() ->
    ?assertEqual({note_tender_award, ok},
                 mcl_tenders_pipeline:reported(fact(#{notice_type => <<"award">>,
                                                      publication_number => <<"760001-2026">>,
                                                      published_at => 1797000000000}))),
    mcl_tenders_pipeline:eventually(field(?TENDER, award_publication_number), <<"760001-2026">>),
    ?assertEqual(1797000000000, field_of(by_id(?TENDER), award_published_at)),
    ?assertEqual({note_tender_award, already_noted},
                 mcl_tenders_pipeline:reported(fact(#{notice_type => <<"award">>,
                                                      publication_number => <<"760002-2026">>}))).

%% T13: the dismissal names the node that signed the call, never a payload field.
a_dismissal_hides_the_tender_and_names_the_caller() ->
    ?assertEqual({<<"dismiss_tender">>, #{}},
                 mcl_tenders_pipeline:call(<<"dismiss_tender">>,
                                           #{tender_id => {text, ?TENDER},
                                             dismissed_by => {text, <<"someone-else">>}},
                                           ?MEMBER)),
    mcl_tenders_pipeline:eventually(fun() -> ids(#{}) end, []),
    ?assertEqual([?TENDER], ids(#{include_dismissed => 1})),
    {ok, D} = by_id(?TENDER),
    ?assertEqual(binary:encode_hex(?MEMBER, lowercase), maps:get(dismissed_by, D)),
    ?assert(maps:get(dismissed_at, D) > 0),
    ?assertEqual(?TENDER_SPOTTED bor ?TENDER_AMENDED bor ?TENDER_AWARD_PUBLISHED bor ?TENDER_DISMISSED,
                 maps:get(status, D)),
    ?assertEqual({<<"dismiss_tender">>, #{<<"reason">> => {text, <<"already_dismissed">>}}},
                 mcl_tenders_pipeline:call(<<"dismiss_tender">>, #{tender_id => {text, ?TENDER}}, ?MEMBER)),
    ?assertEqual({<<"dismiss_tender">>, #{<<"reason">> => {text, <<"not_found">>}}},
                 mcl_tenders_pipeline:call(<<"dismiss_tender">>, #{tender_id => {text, <<"never-1">>}},
                                           ?MEMBER)),
    ?assertEqual({<<"dismiss_tender">>, #{<<"reason">> => {text, <<"no_caller">>}}},
                 mcl_tenders_pipeline:call(<<"dismiss_tender">>, #{tender_id => {text, ?TENDER}},
                                           undefined)).

%% Spotted with a publication time before the later tests' `since', so the
%% pursuits here stay off the pages those tests count.
spotted_early(Id) ->
    {spot_tender, ok} = mcl_tenders_pipeline:reported(fact(#{procedure_id => Id, published_at => 10})).

pursuit_call(Name, Id, Extra, Caller) ->
    mcl_tenders_pipeline:call(Name, maps:merge(#{tender_id => {text, Id}}, Extra), Caller).

%% T13: every step of the pursuit names the node that signed its call, never a
%% payload field; the text list says where it stands.
a_pursuit_runs_from_bid_to_outcome_and_names_each_caller() ->
    Id = <<"pursuit-won-1">>,
    spotted_early(Id),
    Forged = {text, <<"someone-else">>},
    ?assertEqual({<<"pursue_tender">>, #{}},
                 pursuit_call(<<"pursue_tender">>, Id, #{pursued_by => Forged}, ?MEMBER)),
    ?assertEqual({<<"dismiss_tender">>, #{<<"reason">> => {text, <<"pursued">>}}},
                 pursuit_call(<<"dismiss_tender">>, Id, #{}, ?MEMBER)),
    ?assertEqual({<<"record_tender_outcome">>, #{<<"reason">> => {text, <<"not_submitted">>}}},
                 pursuit_call(<<"record_tender_outcome">>, Id, #{outcome => {text, <<"won">>}}, ?MEMBER)),
    ?assertEqual({<<"submit_tender_bid">>, #{}},
                 pursuit_call(<<"submit_tender_bid">>, Id, #{submitted_by => Forged}, ?MEMBER)),
    ?assertEqual({<<"record_tender_outcome">>, #{<<"reason">> => {text, <<"invalid_outcome">>}}},
                 pursuit_call(<<"record_tender_outcome">>, Id, #{outcome => {text, <<"draw">>}}, ?MEMBER)),
    ?assertEqual({<<"record_tender_outcome">>, #{}},
                 pursuit_call(<<"record_tender_outcome">>, Id,
                              #{outcome => {text, <<"won">>}, recorded_by => Forged}, ?MEMBER)),
    ?assertEqual({<<"record_tender_outcome">>, #{<<"reason">> => {text, <<"already_recorded">>}}},
                 pursuit_call(<<"record_tender_outcome">>, Id, #{outcome => {text, <<"lost">>}}, ?MEMBER)),
    ?assertEqual({<<"decline_tender">>, #{<<"reason">> => {text, <<"already_submitted">>}}},
                 pursuit_call(<<"decline_tender">>, Id, #{}, ?MEMBER)),
    Won = ?TENDER_SPOTTED bor ?TENDER_PURSUED bor ?TENDER_BID_SUBMITTED bor ?TENDER_WON,
    mcl_tenders_pipeline:eventually(field(Id, status), Won),
    mcl_tenders_pipeline:eventually(field(Id, outcome), <<"won">>),
    {ok, D} = by_id(Id),
    Me = binary:encode_hex(?MEMBER, lowercase),
    ?assertMatch(#{pursued_by := Me, submitted_by := Me, outcome_by := Me,
                   declined_by := <<>>, declined_at := 0}, D),
    [?assert(maps:get(K, D) > 0) || K <- [pursued_at, submitted_at, outcome_at]],
    {ok, #{text := Text}} = get_tenders_page:find(realm(), #{since => 10, limit => 100}),
    ?assertMatch({match, _}, re:run(Text, "\\| pursuit: won\n|\\| pursuit: won\\z")),
    [?assertEqual({Name, #{<<"reason">> => {text, <<"no_caller">>}}},
                  pursuit_call(Name, Id, #{outcome => {text, <<"won">>}}, undefined))
     || Name <- [<<"pursue_tender">>, <<"decline_tender">>, <<"submit_tender_bid">>,
                 <<"record_tender_outcome">>]],
    [?assertEqual({Name, #{<<"reason">> => {text, <<"not_found">>}}},
                  pursuit_call(Name, <<"never-1">>, #{outcome => {text, <<"won">>}}, ?MEMBER))
     || Name <- [<<"pursue_tender">>, <<"decline_tender">>, <<"submit_tender_bid">>,
                 <<"record_tender_outcome">>]].

a_declined_pursuit_reads_declined() ->
    Id = <<"pursuit-declined-1">>,
    spotted_early(Id),
    ?assertEqual({<<"decline_tender">>, #{<<"reason">> => {text, <<"not_pursued">>}}},
                 pursuit_call(<<"decline_tender">>, Id, #{}, ?MEMBER)),
    ?assertEqual({<<"pursue_tender">>, #{}}, pursuit_call(<<"pursue_tender">>, Id, #{}, ?MEMBER)),
    ?assertEqual({<<"pursue_tender">>, #{<<"reason">> => {text, <<"already_pursued">>}}},
                 pursuit_call(<<"pursue_tender">>, Id, #{}, ?MEMBER)),
    ?assertEqual({<<"decline_tender">>, #{}},
                 pursuit_call(<<"decline_tender">>, Id, #{declined_by => {text, <<"someone-else">>}},
                              ?MEMBER)),
    ?assertEqual({<<"submit_tender_bid">>, #{<<"reason">> => {text, <<"declined">>}}},
                 pursuit_call(<<"submit_tender_bid">>, Id, #{}, ?MEMBER)),
    mcl_tenders_pipeline:eventually(field(Id, status),
                                    ?TENDER_SPOTTED bor ?TENDER_PURSUED bor ?TENDER_DECLINED),
    Me = binary:encode_hex(?MEMBER, lowercase),
    ?assertMatch({ok, #{declined_by := Me, submitted_by := <<>>, outcome := <<>>}}, by_id(Id)),
    %% The dismissed tender of the test before is not pursued.
    ?assertEqual({<<"pursue_tender">>, #{<<"reason">> => {text, <<"dismissed">>}}},
                 pursuit_call(<<"pursue_tender">>, ?TENDER, #{}, ?MEMBER)).

%% The projection's LOST flag, read back against tender_status.hrl.
a_lost_pursuit_reads_lost() ->
    Id = <<"pursuit-lost-1">>,
    spotted_early(Id),
    [?assertEqual({Name, #{}}, pursuit_call(Name, Id, Extra, ?MEMBER))
     || {Name, Extra} <- [{<<"pursue_tender">>, #{}}, {<<"submit_tender_bid">>, #{}},
                          {<<"record_tender_outcome">>, #{outcome => {text, <<"lost">>}}}]],
    mcl_tenders_pipeline:eventually(
      field(Id, status), ?TENDER_SPOTTED bor ?TENDER_PURSUED bor ?TENDER_BID_SUBMITTED bor ?TENDER_LOST),
    ?assertMatch({ok, #{outcome := <<"lost">>}}, by_id(Id)).

%% Most keywords hit first, then the newest; `since' and `limit' bound it.
the_list_is_best_first_and_bounded() ->
    Spot = fun(Id, Published, Description) ->
                   {spot_tender, ok} =
                       mcl_tenders_pipeline:reported(
                         fact(#{procedure_id => Id, published_at => Published,
                                titles => #{<<"eng">> => <<"Software">>},
                                description => Description}))
           end,
    Spot(<<"rank-one-old">>, 1000, <<"erlang">>),
    Spot(<<"rank-one-new">>, 3000, <<"erlang">>),
    Spot(<<"rank-two">>, 2000, <<"erlang, openbare orde">>),
    Want = [<<"rank-two">>, <<"rank-one-new">>, <<"rank-one-old">>],
    mcl_tenders_pipeline:eventually(fun() -> ids(#{since => 1000}) end, Want),
    ?assertEqual([<<"rank-two">>, <<"rank-one-new">>], ids(#{since => 2000})),
    ?assertEqual([<<"rank-two">>], ids(#{since => 1000, limit => 1})).

%% Projections run per event type in their own handlers, so a correction can
%% land before the spot it follows. Its values stay; the spot fills the rest.
a_correction_projected_before_its_spot_is_kept() ->
    Realm = realm(),
    Id = <<"out-of-order-1">>,
    {ok, _} = tender_amended_v1_to_tenders:handle_event(
                <<"tender_amended_v1">>,
                #{data => #{realm => Realm, tender_id => Id, publication_number => <<"770001-2026">>,
                            deadline_at => 1799000000000, estimated_value => <<>>, currency => <<>>,
                            titles => #{}, description => <<"Corrected">>, description_lang => <<"eng">>,
                            published_at => 0, amended_at => 5},
                  version => 1}, #{}, #{}),
    ?assertEqual({error, not_found}, by_id(Id)),
    {ok, _} = tender_spotted_v1_to_tenders:handle_event(
                <<"tender_spotted_v1">>,
                #{data => maps:merge(tender_notice_fixture:notice(),
                                     #{realm => Realm, tender_id => Id, matched_cpv_codes => [],
                                       matched_keywords => [], spotted_at => 4})}, #{}, #{}),
    {ok, D} = by_id(Id),
    ?assertMatch(#{deadline_at := 1799000000000, description := <<"Corrected">>,
                   description_lang := <<"eng">>, estimated_value := <<"1257827.41">>,
                   corrected_by := <<"770001-2026">>, status := ?TENDER_SPOTTED bor ?TENDER_AMENDED},
                 D),
    %% An older correction replayed after a newer one changes nothing.
    {ok, _} = tender_amended_v1_to_tenders:handle_event(
                <<"tender_amended_v1">>,
                #{data => #{realm => Realm, tender_id => Id, publication_number => <<"769999-2026">>,
                            deadline_at => 1, estimated_value => <<>>, currency => <<>>,
                            titles => #{}, description => <<>>, description_lang => <<>>,
                            published_at => 0, amended_at => 1},
                  version => 0}, #{}, #{}),
    ?assertMatch({ok, #{deadline_at := 1799000000000, corrected_by := <<"770001-2026">>}}, by_id(Id)).

a_correction_of_a_tender_never_spotted_is_not_listed() ->
    ?assertEqual({amend_tender, not_spotted},
                 mcl_tenders_pipeline:reported(fact(#{notice_type => <<"correction">>,
                                                      procedure_id => <<"never-spotted">>}))),
    ?assertEqual({error, not_found}, by_id(<<"never-spotted">>)).

the_queries_check_what_they_are_asked() ->
    [?assertEqual({error, invalid_page}, get_tenders_page:find(realm(), Opts))
     || Opts <- [#{limit => 0}, #{limit => 101}, #{since => -1}, #{include_dismissed => 2},
                 #{limit => <<"5">>}]],
    ?assertEqual({error, invalid_realm}, get_tenders_page:find(<<"io.example">>, #{})),
    ?assertEqual({error, invalid_realm}, get_tender_by_id:find(<<"io.example">>, ?TENDER)),
    [?assertEqual({error, invalid_tender_id}, get_tender_by_id:find(realm(), Bad))
     || Bad <- [<<>>, binary:copy(<<"a">>, 65), 42, undefined]].

%%--------------------------------------------------------------------
%% The read model's shape
%%--------------------------------------------------------------------

%% Every column a query desk selects is one the schema creates in that table.
%% (The flags each projection ORs into `status' are held to tender_status.hrl
%% by the dossier tests above, which read the combined status back.)
every_selected_column_is_in_the_schema_test() ->
    [?assertEqual({Desk, []}, {Desk, Columns -- table_columns(Table)})
     || {Desk, Table, Columns} <- [{get_tenders_page, "tenders", get_tenders_page:columns()},
                                   {get_tender_by_id, "tenders", get_tender_by_id:columns()},
                                   {get_tender_profile, "tender_profiles",
                                    get_tender_profile:columns()}]].

%% A table's columns, as the schema creates it and every migration since adds
%% to it: what a box has after its boot, whichever release it started on.
table_columns(Table) ->
    Statements = tenders_read_model_store:schema()
        ++ lists:append([S || {_Version, S} <- tenders_read_model_store:migrations()]),
    [Create] = [S || S <- Statements,
                     string:prefix(S, "CREATE TABLE IF NOT EXISTS " ++ Table ++ " (") =/= nomatch],
    {match, Names} = re:run(Create, "[(,] *([a-z_]+) +(?:TEXT|INTEGER)",
                           [global, {capture, all_but_first, list}]),
    Added = [Column || S <- Statements,
                       {match, [Column]} <- [re:run(S, "^ALTER TABLE " ++ Table ++ " ADD COLUMN ([a-z_]+) ",
                                                    [{capture, all_but_first, list}])]],
    lists:append(Names) ++ Added.

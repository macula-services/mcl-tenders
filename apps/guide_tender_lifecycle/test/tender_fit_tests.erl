%%% @doc The keyword fit (#4a): country, CPV hierarchy, exclusions, keywords.
-module(tender_fit_tests).

-include_lib("eunit/include/eunit.hrl").

-import(tender_notice_fixture, [notice/0, notice/1, profile/0, profile/1]).

a_profile_with_no_keywords_fits_on_codes_and_countries_test() ->
    ?assertEqual({fits, #{matched_cpv_codes => [<<"72000000">>], matched_keywords => []}},
                 tender_fit:fit(notice(), profile())).

a_buyer_country_outside_the_profile_does_not_fit_test() ->
    ?assertEqual({no_fit, country}, tender_fit:fit(notice(#{buyer_country => <<"FRA">>}), profile())),
    ?assertEqual({no_fit, country}, tender_fit:fit(notice(#{buyer_country => <<>>}), profile())).

cpv_is_a_hierarchy_test() ->
    ?assert(tender_fit:covers(<<"72000000">>, <<"72315000">>)),
    ?assert(tender_fit:covers(<<"72300000">>, <<"72315000">>)),
    ?assert(tender_fit:covers(<<"72315000">>, <<"72315000">>)),
    ?assertNot(tender_fit:covers(<<"72300000">>, <<"72260000">>)),
    ?assertNot(tender_fit:covers(<<"72000000">>, <<"71000000">>)),
    %% Never less than the division: 70000000 does not cover all of 7x.
    ?assertNot(tender_fit:covers(<<"70000000">>, <<"72000000">>)).

no_profile_code_covering_a_notice_code_does_not_fit_test() ->
    ?assertEqual({no_fit, cpv_code},
                 tender_fit:fit(notice(), profile(#{cpv_codes => [<<"45000000">>]}))),
    ?assertEqual({no_fit, cpv_code}, tender_fit:fit(notice(#{cpv_codes => []}), profile())).

every_profile_code_that_covers_is_a_reason_test() ->
    ?assertMatch({fits, #{matched_cpv_codes := [<<"72000000">>, <<"48000000">>]}},
                 tender_fit:fit(notice(), profile(#{cpv_codes => [<<"72000000">>, <<"45000000">>,
                                                                  <<"48000000">>]}))).

an_exclusion_in_a_title_or_the_description_does_not_fit_test() ->
    ?assertEqual({no_fit, exclusion},
                 tender_fit:fit(notice(), profile(#{exclusions => [<<"OPENBARE ORDE">>]}))),
    ?assertEqual({no_fit, exclusion},
                 tender_fit:fit(notice(), profile(#{exclusions => [<<"gemeente zoekt">>],
                                                    keywords => [<<"erlang">>]}))).

keywords_match_case_folded_substrings_test() ->
    ?assertEqual({fits, #{matched_cpv_codes => [<<"72000000">>], matched_keywords => [<<"ERLANG">>]}},
                 tender_fit:fit(notice(), profile(#{keywords => [<<"ERLANG">>, <<"elixir">>]}))),
    %% Unicode case folding: STRASSE finds Straße.
    ?assertMatch({fits, #{matched_keywords := [<<"STRASSE">>]}},
                 tender_fit:fit(notice(#{description => <<"Hauptstraße"/utf8>>}),
                                profile(#{keywords => [<<"STRASSE">>]}))).

no_keyword_hit_does_not_fit_test() ->
    ?assertEqual({no_fit, keyword}, tender_fit:fit(notice(), profile(#{keywords => [<<"elixir">>]}))).

a_term_never_matches_across_two_texts_test() ->
    N = notice(#{titles => #{<<"eng">> => <<"open">>}, description => <<"source">>}),
    ?assertEqual({no_fit, keyword}, tender_fit:fit(N, profile(#{keywords => [<<"opensource">>]}))).

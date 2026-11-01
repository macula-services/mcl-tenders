%%% @doc A notice read again from its fact (T4, T6): the dossier trusts none
%%% of the fact's text.
-module(tender_notice_tests).

-include_lib("eunit/include/eunit.hrl").

-import(tender_notice_fixture, [fact/0, fact/1, notice/0, notice/1]).

every_field_is_read_from_the_wire_form_test() ->
    ?assertEqual(#{publication_number => <<"745687-2026">>,
                   procedure_id => <<"85e562c1-17d1-4192-a543-082edb9b62ab">>,
                   notice_type => <<"contract_notice">>, buyer_name => <<"Gemeente Voorbeeld">>,
                   buyer_country => <<"NLD">>, cpv_codes => [<<"48000000">>, <<"72260000">>],
                   titles => #{<<"eng">> => <<"Application for public order">>,
                               <<"nld">> => <<"Applicatie voor openbare orde">>},
                   description => <<"De gemeente zoekt een Erlang-applicatie.">>,
                   description_lang => <<"nld">>, deadline_at => 1795000000000,
                   estimated_value => <<"1257827.41">>, currency => <<"EUR">>,
                   published_at => 1793000000000, source => <<"ted">>},
                 notice()).

a_publication_number_not_in_teds_form_drops_the_notice_test() ->
    [?assertEqual({skip, publication_number},
                  tender_notice:from_fact(fact(#{publication_number => Bad})))
     || Bad <- [<<>>, <<"745687">>, <<"745687-2026/../x">>, <<"https://phish.example">>,
                <<"123456789-2026">>, <<"745687-2026\n">>]],
    ?assertEqual({skip, publication_number},
                 tender_notice:from_fact(maps:remove({text, <<"publication_number">>}, fact()))),
    ?assertEqual({skip, publication_number}, tender_notice:from_fact(not_a_map)).

a_notice_type_outside_the_four_drops_the_notice_test() ->
    ?assertEqual({skip, notice_type}, tender_notice:from_fact(fact(#{notice_type => <<"cancellation">>}))).

%% The field list is closed: a link or any other field a fact carries is not
%% read, so no link from a payload is ever shown (T4).
a_field_outside_the_list_is_not_read_test() ->
    N = notice(#{url => <<"https://phish.example/notice">>, buyer_email => <<"x@example.org">>}),
    ?assertEqual(lists:sort(tender_notice:fields()), lists:sort(maps:keys(N))).

a_code_that_is_not_a_code_is_dropped_test() ->
    N = notice(#{cpv_codes => [<<"7226000">>, <<"72260000-1">>, <<"72260000">>, 42],
                 buyer_country => <<"nl">>, currency => <<"EURO">>,
                 description_lang => <<"NL">>, estimated_value => <<"1e9">>,
                 procedure_id => <<"a b">>}),
    ?assertMatch(#{cpv_codes := [<<"72260000">>], buyer_country := <<>>, currency := <<>>,
                   description_lang := <<>>, estimated_value := <<>>, procedure_id := <<>>}, N).

text_past_its_bound_or_not_utf8_is_dropped_test() ->
    N = notice(#{description => binary:copy(<<"a">>, 6001), buyer_name => <<255, 254>>,
                 titles => #{<<"eng">> => binary:copy(<<"t">>, 1601), <<"nld">> => <<"Kort">>}}),
    ?assertMatch(#{description := <<>>, buyer_name := <<>>,
                   titles := #{<<"eng">> := <<>>, <<"nld">> := <<"Kort">>}}, N).

titles_keep_six_languages_with_a_valid_code_test() ->
    Titles = maps:from_list([{L, <<"T">>} || L <- [<<"bul">>, <<"ces">>, <<"dan">>, <<"deu">>,
                                                 <<"ell">>, <<"eng">>, <<"fra">>, <<"EN">>]]),
    #{titles := Kept} = notice(#{titles => Titles}),
    ?assertEqual([<<"bul">>, <<"ces">>, <<"dan">>, <<"deu">>, <<"ell">>, <<"eng">>],
                 lists:sort(maps:keys(Kept))).

a_count_that_is_not_a_count_is_zero_test() ->
    ?assertMatch(#{deadline_at := 0, published_at := 0},
                 notice(#{deadline_at => -1, published_at => <<"yesterday">>})).

the_dossier_is_the_procedure_or_else_the_notice_test() ->
    ?assertEqual(<<"85e562c1-17d1-4192-a543-082edb9b62ab">>, tender_notice:tender_id(notice())),
    ?assertEqual(<<"745687-2026">>, tender_notice:tender_id(notice(#{procedure_id => <<>>}))).

a_tender_id_a_caller_sends_is_checked_test() ->
    ?assert(tender_notice:valid_tender_id(<<"745687-2026">>)),
    [?assertNot(tender_notice:valid_tender_id(Bad))
     || Bad <- [<<>>, <<"a b">>, <<"x/y">>, binary:copy(<<"a">>, 65), 42, undefined]].

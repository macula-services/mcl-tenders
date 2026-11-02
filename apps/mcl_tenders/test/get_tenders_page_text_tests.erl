%%% @doc The morning list as text: what an agent answers "any tenders today?"
%%% with. One line per tender, best first, with title, buyer, country,
%%% deadline and TED notice id, and where the pursuit stands once there is
%%% one; nothing else.
-module(get_tenders_page_text_tests).

-include_lib("eunit/include/eunit.hrl").
-include_lib("guide_tender_lifecycle/src/tender_status.hrl").

-define(DEADLINE, 1796083200000). %% 2026-12-01T00:00:00Z

summary(Overrides) ->
    maps:merge(#{tender_id => <<"t-1">>, publication_number => <<"712345-2026">>,
                 notice_type => <<"contract_notice">>, buyer_name => <<"Stad Leuven">>,
                 buyer_country => <<"BEL">>,
                 titles => [#{lang => <<"ENG">>, title => <<"Road works">>},
                            #{lang => <<"NLD">>, title => <<"Wegenwerken">>}],
                 deadline_at => ?DEADLINE, estimated_value => <<>>, currency => <<>>,
                 published_at => 0, status => 1, matched_cpv_codes => [<<"45233000">>],
                 matched_keywords => [<<"weg">>], ted_url => <<"https://ted.europa.eu/x">>},
               Overrides).

an_empty_list_says_so_test() ->
    ?assertEqual(<<"No tenders on the list.">>, get_tenders_page_text:rendered([])).

one_line_per_tender_in_order_test() ->
    Text = get_tenders_page_text:rendered(
             [summary(#{}),
              summary(#{publication_number => <<"8-2026">>, buyer_name => <<"Gemeente Utrecht">>,
                        buyer_country => <<"NLD">>, deadline_at => 0,
                        titles => [#{lang => <<"NLD">>, title => <<"Software">>}]})]),
    ?assertEqual(<<"2 tenders (best first):\n"
                   "1. Road works | buyer: Stad Leuven (BEL) | deadline: 2026-12-01T00:00:00.000Z"
                   " | notice: 712345-2026\n"
                   "2. Software | buyer: Gemeente Utrecht (NLD) | deadline: none given"
                   " | notice: 8-2026">>, Text).

english_title_first_else_the_first_given_test() ->
    Nld = #{lang => <<"NLD">>, title => <<"Wegenwerken">>},
    ?assertMatch({match, _}, re:run(get_tenders_page_text:rendered([summary(#{})]), "1\\. Road works")),
    ?assertMatch({match, _}, re:run(get_tenders_page_text:rendered([summary(#{titles => [Nld]})]),
                                    "1\\. Wegenwerken")),
    ?assertMatch({match, _}, re:run(get_tenders_page_text:rendered([summary(#{titles => []})]),
                                    "1\\. \\(no title\\)")).

a_line_break_in_a_notice_keeps_one_tender_one_line_test() ->
    Text = get_tenders_page_text:rendered(
             [summary(#{buyer_name => <<"Stad\r\nLeuven">>,
                        titles => [#{lang => <<"ENG">>, title => <<"Road\nworks">>}]})]),
    ?assertEqual(2, length(binary:split(Text, <<"\n">>, [global]))),
    ?assertMatch({match, _}, re:run(Text, "Road works \\| buyer: Stad Leuven")).

%% No link and no profile term: the summary's other fields stay out.
carries_nothing_but_the_five_fields_test() ->
    Text = get_tenders_page_text:rendered([summary(#{})]),
    [?assertEqual(nomatch, binary:match(Text, Absent))
     || Absent <- [<<"https://">>, <<"45233000">>, <<"weg ">>, <<"t-1">>, <<"contract_notice">>]].

an_unknown_buyer_reads_unknown_test() ->
    Text = get_tenders_page_text:rendered([summary(#{buyer_name => <<>>, buyer_country => <<>>})]),
    ?assertMatch({match, _}, re:run(Text, "buyer: unknown \\(unknown\\)")).

%% The furthest step of the pursuit, at the end of the line; none before it.
the_pursuit_ends_the_line_test() ->
    Line = fun(Status) -> get_tenders_page_text:rendered([summary(#{status => Status})]) end,
    ?assertEqual(nomatch, binary:match(Line(?TENDER_SPOTTED bor ?TENDER_AMENDED), <<"pursuit">>)),
    [?assertMatch({match, _}, re:run(Line(Status), "notice: 712345-2026 \\| pursuit: " ++ Word ++ "\\z"))
     || {Status, Word} <- [{?TENDER_PURSUED, "pursuing"},
                           {?TENDER_PURSUED bor ?TENDER_BID_SUBMITTED, "bid submitted"},
                           {?TENDER_PURSUED bor ?TENDER_DECLINED, "declined"},
                           {?TENDER_PURSUED bor ?TENDER_BID_SUBMITTED bor ?TENDER_WON, "won"},
                           {?TENDER_PURSUED bor ?TENDER_BID_SUBMITTED bor ?TENDER_LOST, "lost"}]].

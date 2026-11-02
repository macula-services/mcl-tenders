%%% @doc What a tenders profile may say. CPV codes and countries are codes and
%%% nothing else, because the sensor puts them in its query to TED (T3, T6);
%%% keywords, exclusions and the description are NFC text with no control or
%%% invisible format character; every list and every text is bounded.
-module(describe_tender_profile_v1_tests).

-include_lib("eunit/include/eunit.hrl").

-define(REALM, <<16#5e:256>>).
-define(MEMBER, <<16#a1:256>>).

new(Fields) ->
    describe_tender_profile_v1:new(maps:merge(#{realm => ?REALM, described_by => ?MEMBER}, Fields)).

get(Field, {ok, Cmd}) -> maps:get(Field, describe_tender_profile_v1:to_map(Cmd)).

an_empty_profile_is_a_profile_test() ->
    {ok, Cmd} = new(#{}),
    ?assertMatch(#{cpv_codes := [], countries := [], keywords := [], exclusions := [],
                   description := <<>>}, describe_tender_profile_v1:to_map(Cmd)).

codes_are_sorted_and_deduplicated_test() ->
    Cmd = new(#{cpv_codes => [<<"72000000">>, <<"48000000">>, <<"72000000">>],
                countries => [<<"NLD">>, <<"BEL">>, <<"BEL">>]}),
    ?assertEqual([<<"48000000">>, <<"72000000">>], get(cpv_codes, Cmd)),
    ?assertEqual([<<"BEL">>, <<"NLD">>], get(countries, Cmd)).

%% Every list, not only the codes: one term written twice, or twice in two
%% normal forms, is one term.
keywords_and_exclusions_are_sorted_and_deduplicated_test() ->
    Decomposed = <<"Cafe", 16#cc, 16#81>>,
    Composed = <<"Caf", 16#c3, 16#a9>>,
    Cmd = new(#{keywords => [<<"b">>, <<"a">>, <<"a">>, Decomposed, Composed],
                exclusions => [<<"z">>, <<"z">>]}),
    ?assertEqual([Composed, <<"a">>, <<"b">>], get(keywords, Cmd)),
    ?assertEqual([<<"z">>], get(exclusions, Cmd)).

a_cpv_code_is_eight_digits_test_() ->
    [?_assertEqual({error, invalid_cpv_codes}, new(#{cpv_codes => [Bad]}))
     || Bad <- [<<"7200000">>, <<"720000000">>, <<"72000000-6">>, <<"7200000a">>,
                <<" 72000000">>, <<"72000000\n">>, 72000000, <<>>]] ++
    [?_assertEqual({error, invalid_cpv_codes}, new(#{cpv_codes => <<"72000000">>})),
     ?_assertEqual({error, invalid_cpv_codes},
                   new(#{cpv_codes => [<<(integer_to_binary(10_000_000 + N))/binary>>
                                       || N <- lists:seq(1, 101)]})),
     ?_assertMatch({ok, _},
                   new(#{cpv_codes => [<<(integer_to_binary(10_000_000 + N))/binary>>
                                       || N <- lists:seq(1, 100)]}))].

a_country_is_three_capital_letters_test_() ->
    [?_assertEqual({error, invalid_countries}, new(#{countries => [Bad]}))
     || Bad <- [<<"BE">>, <<"bel">>, <<"BELG">>, <<"B3L">>, <<"BÉL"/utf8>>, bel, <<>>]] ++
    [?_assertEqual({error, invalid_countries},
                   new(#{countries => [<<"BEL">> || _ <- lists:seq(1, 41)]}))].

text_is_stored_in_nfc_test() ->
    Decomposed = <<"Cafe", 16#cc, 16#81>>,
    Composed = <<"Caf", 16#c3, 16#a9>>,
    Cmd = new(#{keywords => [Decomposed], exclusions => [Decomposed], description => Decomposed}),
    ?assertEqual([Composed], get(keywords, Cmd)),
    ?assertEqual([Composed], get(exclusions, Cmd)),
    ?assertEqual(Composed, get(description, Cmd)).

any_script_is_fine_test() ->
    ?assertMatch({ok, _}, new(#{keywords => [<<"event sourcing">>, <<"Ereignisspeicher">>,
                                             <<"イベントストア"/utf8>>],
                                description => <<"Nous construisons des bases de données."/utf8>>})).

%% The description is a paragraph or several: a line feed is allowed there,
%% and nowhere else.
the_description_may_span_lines_test() ->
    ?assertMatch({ok, _}, new(#{description => <<"First line.\nSecond line.">>})),
    ?assertEqual({error, invalid_keywords}, new(#{keywords => [<<"two\nlines">>]})).

invisible_and_control_characters_are_refused_test_() ->
    Bad = [<<"evil", 16#e2, 16#80, 16#ae, "txet">>,      %% U+202E right-to-left override
           <<"pad", 16#e2, 16#80, 16#8b>>,               %% U+200B zero-width space
           <<"iso", 16#e2, 16#81, 16#a6, "x">>,          %% U+2066 left-to-right isolate
           <<16#ef, 16#bb, 16#bf, "bom">>,               %% U+FEFF
           <<"line", 16#e2, 16#80, 16#a8, "sep">>,       %% U+2028
           <<"soft", 16#c2, 16#ad, "hyphen">>,           %% U+00AD
           <<"a", 16#f3, 16#a0, 16#81, 16#81>>,          %% U+E0041 tag latin capital A
           <<"ann", 16#ef, 16#bf, 16#b9, "ot">>,         %% U+FFF9 interlinear annotation anchor
           <<"ann", 16#ef, 16#bf, 16#bb, "ot">>,         %% U+FFFB interlinear annotation terminator
           <<"un", 16#e2, 16#81, 16#a5, "set">>,         %% U+2065, unassigned
           <<"tab\there">>, <<"cr\r">>, <<16#c2, 16#85>>, <<255>>],
    [?_assertEqual({error, invalid_keywords}, new(#{keywords => [B]})) || B <- Bad] ++
    [?_assertEqual({error, invalid_exclusions}, new(#{exclusions => [B]})) || B <- Bad] ++
    [?_assertEqual({error, invalid_description}, new(#{description => B})) || B <- Bad].

sizes_are_bounded_test() ->
    A = fun(N) -> binary:copy(<<"a">>, N) end,
    ?assertEqual({error, invalid_keywords}, new(#{keywords => [<<>>]})),
    ?assertEqual({error, invalid_keywords}, new(#{keywords => [A(101)]})),
    ?assertMatch({ok, _}, new(#{keywords => [A(100)]})),
    ?assertEqual({error, invalid_keywords}, new(#{keywords => lists:duplicate(51, <<"x">>)})),
    ?assertMatch({ok, _}, new(#{keywords => lists:duplicate(50, <<"x">>)})),
    ?assertEqual({error, invalid_keywords}, new(#{keywords => <<"not a list">>})),
    ?assertEqual({error, invalid_exclusions}, new(#{exclusions => [A(101)]})),
    ?assertEqual({error, invalid_exclusions}, new(#{exclusions => lists:duplicate(51, <<"x">>)})),
    ?assertEqual({error, invalid_description}, new(#{description => A(4001)})),
    ?assertMatch({ok, _}, new(#{description => A(4000)})).

a_command_without_a_32_byte_realm_or_member_is_refused_test() ->
    ?assertEqual({error, invalid_realm},
                 describe_tender_profile_v1:new(#{described_by => ?MEMBER})),
    ?assertEqual({error, invalid_realm},
                 describe_tender_profile_v1:new(#{realm => <<1:248>>, described_by => ?MEMBER})),
    ?assertEqual({error, no_caller}, describe_tender_profile_v1:new(#{realm => ?REALM})),
    ?assertEqual({error, no_caller},
                 describe_tender_profile_v1:new(#{realm => ?REALM, described_by => <<1:248>>})).

the_command_and_event_survive_their_maps_test() ->
    {ok, Cmd} = new(#{cpv_codes => [<<"72000000">>], keywords => [<<"Erlang">>],
                      description => <<"d">>}),
    ?assertEqual({ok, Cmd}, describe_tender_profile_v1:from_map(describe_tender_profile_v1:to_map(Cmd))),
    Ev = tender_profile_described_v1:new(#{realm => ?REALM, described_by => ?MEMBER,
                                           cpv_codes => [], countries => [], keywords => [],
                                           exclusions => [], description => <<>>,
                                           described_at => 3}),
    ?assertEqual({ok, Ev}, tender_profile_described_v1:from_map(tender_profile_described_v1:to_map(Ev))).

%% `unless_described' is 0 or 1, 0 when absent, and travels in the command's
%% map so the aggregate reads it; a command rebuilt from an older map is 0.
unless_described_is_zero_or_one_test() ->
    Base = #{realm => <<1:256>>, described_by => <<2:256>>,
             cpv_codes => [<<"72000000">>], countries => [<<"BEL">>]},
    {ok, Plain} = describe_tender_profile_v1:new(Base),
    ?assertEqual(0, describe_tender_profile_v1:unless_described(Plain)),
    {ok, Once} = describe_tender_profile_v1:new(Base#{unless_described => 1}),
    ?assertMatch(#{unless_described := 1}, describe_tender_profile_v1:to_map(Once)),
    {ok, Rebuilt} = describe_tender_profile_v1:from_map(describe_tender_profile_v1:to_map(Once)),
    ?assertEqual(1, describe_tender_profile_v1:unless_described(Rebuilt)),
    {ok, Old} = describe_tender_profile_v1:from_map(
                  maps:remove(unless_described, describe_tender_profile_v1:to_map(Once))),
    ?assertEqual(0, describe_tender_profile_v1:unless_described(Old)),
    [?assertEqual({error, invalid_unless_described},
                  describe_tender_profile_v1:new(Base#{unless_described => V}))
     || V <- [2, true, <<"1">>]].

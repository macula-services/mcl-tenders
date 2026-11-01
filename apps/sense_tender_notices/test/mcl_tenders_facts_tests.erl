%%% @doc The public contract: its one fact topic, and the fact itself. Pure:
%%% no network, no mesh (the publish is integration).
%%%
%%% The fact is what every company node matches on, so it carries everything
%%% matching needs and nothing else: a company never has to ask the sensor a
%%% follow-up question, which would tell the sensor what it is interested in
%%% (T3), and no contact data TED holds leaves the sensor (A5).
-module(mcl_tenders_facts_tests).

-include_lib("eunit/include/eunit.hrl").

-define(FIELDS, [publication_number, procedure_id, notice_type, buyer_name, buyer_country,
                 cpv_codes, titles, description, description_lang, deadline_at,
                 estimated_value, currency, published_at, source]).

notice() ->
    {ok, N} = parse_ted_notice:parse(ted_notice_fixture:notice()),
    N.

fact() -> mcl_tenders_facts:fact(notice()).

%% ONE topic for every notice, whatever its country or CPV code: a topic per
%% code would tell any station which codes a company subscribed to (T3).
the_topic_is_one_app_fact_of_this_org_test() ->
    ?assertEqual(macula_topic:app_fact(<<"io.macula">>, <<"mcl-tenders">>, <<"tenders">>,
                                       <<"wire">>, <<"tender_notice_reported">>, 1),
                 mcl_tenders_facts:topic(<<"io.macula">>)).

%% THE FIELD LIST IS CLOSED AND PINNED. Adding a field is a change to the
%% public contract every company node builds against, so it breaks this test
%% and someone writes down why. It has no url (T4: the node rebuilds the TED
%% link from the publication number) and no contact field (A5).
the_fact_carries_exactly_the_contract_fields_test() ->
    ?assertEqual(lists:sort(?FIELDS), lists:sort(maps:keys(fact()))),
    ?assertEqual(lists:sort(?FIELDS), lists:sort(mcl_tenders_facts:fields())).

%% A5: a notice that carries contact people, phone numbers, e-mail addresses
%% and a link yields a fact without any of them, even when the parser was
%% handed them (closed list), and even when they sit in the parsed map.
no_contact_data_reaches_the_fact_test() ->
    Leaky = (notice())#{buyer_email => <<"inkoop@voorbeeld.example">>,
                        url => <<"https://phish.example/notice">>},
    Values = all_text(mcl_tenders_facts:fact(Leaky)),
    ?assertEqual([], [V || V <- ted_notice_fixture:contact_values(),
                           lists:any(fun(T) -> binary:match(T, V) =/= nomatch end, Values)]).

the_fact_carries_the_notice_test() ->
    F = fact(),
    ?assertEqual({text, <<"745687-2026">>}, maps:get(publication_number, F)),
    ?assertEqual({text, <<"85e562c1-17d1-4192-a543-082edb9b62ab">>}, maps:get(procedure_id, F)),
    ?assertEqual({text, <<"contract_notice">>}, maps:get(notice_type, F)),
    ?assertEqual({text, <<"NLD">>}, maps:get(buyer_country, F)),
    ?assertEqual([{text, <<"72000000">>}, {text, <<"72260000">>}], maps:get(cpv_codes, F)),
    ?assertEqual({text, <<"nld">>}, maps:get(description_lang, F)),
    ?assertEqual({text, <<"1257827.41">>}, maps:get(estimated_value, F)),
    ?assertEqual({text, <<"EUR">>}, maps:get(currency, F)),
    ?assertEqual({text, <<"ted">>}, maps:get(source, F)),
    ?assertEqual(1793142000000, maps:get(published_at, F)),
    ?assertEqual(1794906000000, maps:get(deadline_at, F)).

%% Titles stay a map, language to title, with text keys and text values.
titles_are_a_text_keyed_map_test() ->
    #{titles := Titles} = fact(),
    ?assertEqual([{text, <<"eng">>}, {text, <<"nld">>}], lists:sort(maps:keys(Titles))),
    ?assertMatch({text, <<"Netherlands", _/binary>>}, maps:get({text, <<"eng">>}, Titles)).

%% A bare binary goes out as a CBOR byte string, which every consumer outside
%% the BEAM renders as 0x-hex; and there are no booleans on the wire at all.
every_string_is_tagged_text_and_nothing_is_a_boolean_test() ->
    F = fact(),
    ?assertEqual([], bare_binaries(F)),
    ?assertEqual([], [V || V <- flatten(F), is_boolean(V)]).

%% Who reported it is the publisher macula verified, never a payload field.
carries_no_self_asserted_sender_test() ->
    F = fact(),
    ?assertNot(lists:any(fun(K) -> maps:is_key(K, F) end, [from, sender, node_id, sensor, url])).

%% T6: notice text reaches a company's agent as data, so every free-text field
%% is bounded, by graphemes so multibyte text is never cut mid-character.
free_text_is_clipped_test() ->
    Long = binary:copy(<<"é"/utf8>>, 5000),
    N = (notice())#{titles => #{<<"eng">> => Long}, description => Long, buyer_name => Long},
    #{titles := #{{text, <<"eng">>} := {text, T}}, description := {text, D},
      buyer_name := {text, B}} = mcl_tenders_facts:fact(N),
    ?assertEqual({301, 1201, 301}, {string:length(T), string:length(D), string:length(B)}).

%% Control characters other than line breaks are dropped from free text: a
%% terminal escape in a buyer's description must not reach a reader's screen.
free_text_carries_no_control_characters_test() ->
    N = (notice())#{description => <<"line one\nline\e[31m two\x{7}">>},
    #{description := {text, D}} = mcl_tenders_facts:fact(N),
    ?assertEqual(<<"line one\nline[31m two">>, D).

%% A fact never carries more than a few kilobytes, whatever TED sends.
a_fact_is_small_test() ->
    Long = binary:copy(<<"x">>, 100000),
    N = (notice())#{titles => maps:from_list([{L, Long} || L <- [<<"eng">>, <<"nld">>, <<"fra">>]]),
                    description => Long, buyer_name => Long,
                    cpv_codes => [integer_to_binary(10000000 + I) || I <- lists:seq(1, 1000)]},
    ?assert(byte_size(term_to_binary(mcl_tenders_facts:fact(N))) < 16384).

%% The topic carries the realm NAME and the pool publishes in the realm TAG.
realm_name_must_hash_to_the_realm_tag_test() ->
    Tag = crypto:hash(sha256, <<"io.macula">>),
    ?assertEqual(ok, mcl_tenders_facts:check_realm_name(<<"io.macula">>, Tag)),
    ?assertError({mcl_tenders_realm_name_mismatch, <<"x">>, Tag},
                 mcl_tenders_facts:check_realm_name(<<"x">>, Tag)).

%% A name that hashes right but is not a valid topic segment would pass the
%% check and then fail every report while /health stays green.
a_realm_name_that_cannot_build_the_topic_is_refused_test() ->
    Name = <<"IO Macula">>,
    ?assertError(_, mcl_tenders_facts:check_realm_name(Name, crypto:hash(sha256, Name))).

realm_name_is_required_test() ->
    _ = application:load(sense_tender_notices),
    ok = application:set_env(sense_tender_notices, realm_name, ""),
    try ?assertError({mcl_tenders_realm_name_unset, realm_name}, mcl_tenders_facts:realm_name())
    after application:unset_env(sense_tender_notices, realm_name)
    end.

%%------------------------------------------------------------------------------

flatten(Map) when is_map(Map) -> lists:append([flatten(K) ++ flatten(V) || {K, V} <- maps:to_list(Map)]);
flatten(List) when is_list(List) -> lists:append([flatten(V) || V <- List]);
flatten({text, Bin}) -> [{text, Bin}];
flatten(Other) -> [Other].

all_text(Fact) -> [B || {text, B} <- flatten(Fact)].

bare_binaries(Fact) -> [B || B <- flatten(Fact), is_binary(B)].

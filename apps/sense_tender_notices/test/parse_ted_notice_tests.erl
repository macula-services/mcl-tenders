%%% @doc One TED Search API notice into the one map the fact is built from.
%%% Pure: no network.
%%%
%%% The Search API answers eForms notices and the older TED-schema ones in one
%%% JSON shape, so this is the only reader the sensor needs. Its field list is
%%% outside the API's versioning and can change without a new version, so a
%%% missing or unknown field must never stop a sweep.
-module(parse_ted_notice_tests).

-include_lib("eunit/include/eunit.hrl").

-define(NOTICE, ted_notice_fixture:notice()).
-define(NOTICE(Overrides), ted_notice_fixture:notice(Overrides)).

parse(Json) ->
    {ok, Notice} = parse_ted_notice:parse(Json),
    Notice.

%% 2026-11-17T10:00:00+01:00 and 2026-10-28T00:00:00+01:00, in ms.
-define(EARLIEST_DEADLINE, 1794906000000).
-define(PUBLISHED, 1793142000000).

carries_the_fields_matching_needs_test() ->
    N = parse(?NOTICE),
    ?assertEqual(<<"745687-2026">>, maps:get(publication_number, N)),
    ?assertEqual(<<"85e562c1-17d1-4192-a543-082edb9b62ab">>, maps:get(procedure_id, N)),
    ?assertEqual(contract_notice, maps:get(notice_type, N)),
    ?assertEqual(<<"Gemeente Voorbeeld">>, maps:get(buyer_name, N)),
    ?assertEqual(<<"NLD">>, maps:get(buyer_country, N)),
    ?assertEqual(<<"De gemeente zoekt een applicatie.">>, maps:get(description, N)),
    ?assertEqual(<<"nld">>, maps:get(description_lang, N)),
    ?assertEqual(<<"1257827.41">>, maps:get(estimated_value, N)),
    ?assertEqual(<<"EUR">>, maps:get(currency, N)),
    ?assertEqual(?PUBLISHED, maps:get(published_at, N)),
    ?assertEqual(ted, maps:get(source, N)).

%% TED repeats a code once per lot; each one is kept once, in order, and
%% anything that is not an eight-digit code is not.
cpv_codes_are_each_kept_once_test() ->
    ?assertEqual([<<"72000000">>, <<"72260000">>], maps:get(cpv_codes, parse(?NOTICE))),
    N = parse(?NOTICE(#{<<"classification-cpv">> => [<<"7200">>, <<"x">>, <<"48000000">>]})),
    ?assertEqual([<<"48000000">>], maps:get(cpv_codes, N)).

%% The title in each language the buyer published in, plus English. TED
%% machine-translates the label part into all 24 languages; carrying all of
%% them would put some 24 copies of every notice's title on the mesh.
titles_are_the_official_languages_and_english_test() ->
    #{titles := Titles} = parse(?NOTICE),
    ?assertEqual([<<"eng">>, <<"nld">>], lists:sort(maps:keys(Titles))).

%% A notice with neither keeps whatever title it has rather than none.
a_notice_without_those_languages_keeps_its_titles_test() ->
    Titles = #{<<"fra">> => <<"Titre">>},
    N = parse(?NOTICE(#{<<"notice-title">> => Titles, <<"official-language">> => [<<"DEU">>]})),
    ?assertEqual(Titles, maps:get(titles, N)).

%% The deadline is the EARLIEST lot's, date and time together, so a company is
%% never told it has longer than it has.
the_deadline_is_the_earliest_lot_test() ->
    ?assertEqual(?EARLIEST_DEADLINE, maps:get(deadline_at, parse(?NOTICE))).

%% A date without a time reads as the start of that day: earlier, never later.
a_deadline_without_a_time_is_the_start_of_its_day_test() ->
    N = parse(maps:remove(<<"deadline-receipt-tender-time-lot">>, ?NOTICE)),
    ?assertEqual(1794870000000, maps:get(deadline_at, N)).

no_deadline_is_zero_test() ->
    ?assertEqual(0, maps:get(deadline_at, parse(maps:remove(<<"deadline-receipt-tender-date-lot">>, ?NOTICE)))).

an_unreadable_date_is_zero_test() ->
    N = parse(?NOTICE(#{<<"publication-date">> => <<"28/10/2026">>,
                        <<"deadline-receipt-tender-date-lot">> => [<<"2026-13-45+01:00">>]})),
    ?assertEqual({0, 0}, {maps:get(published_at, N), maps:get(deadline_at, N)}).

%% A value is a plain decimal or nothing, and a currency only goes with a value.
an_estimated_value_is_a_decimal_or_nothing_test() ->
    N = parse(?NOTICE(#{<<"estimated-value-proc">> => <<"1e9; drop">>})),
    ?assertEqual({<<>>, <<>>}, {maps:get(estimated_value, N), maps:get(currency, N)}),
    M = parse(maps:remove(<<"estimated-value-proc">>, ?NOTICE)),
    ?assertEqual({<<>>, <<>>}, {maps:get(estimated_value, M), maps:get(currency, M)}).

%%------------------------------------------------------------------------------
%% Which notices are reported, and as what
%%------------------------------------------------------------------------------

%% eForms has no "correction" form: a correction is a notice that names the
%% notice it changes (change-notice-version-identifier). Read live: 636 of the
%% 3,862 notices of 28 October 2026 carried one.
the_notice_type_follows_the_form_and_the_change_test() ->
    Type = fun(Form, Change) ->
                   Base = ?NOTICE(#{<<"form-type">> => Form}),
                   maps:get(notice_type, parse(with_change(Base, Change)))
           end,
    ?assertEqual(contract_notice, Type(<<"competition">>, none)),
    ?assertEqual(correction, Type(<<"competition">>, <<"607784-2026">>)),
    ?assertEqual(prior_information, Type(<<"planning">>, none)),
    ?assertEqual(prior_information, Type(<<"consultation">>, none)),
    ?assertEqual(correction, Type(<<"planning">>, <<"607784-2026">>)),
    ?assertEqual(award, Type(<<"result">>, none)),
    ?assertEqual(award, Type(<<"result">>, <<"607784-2026">>)),
    ?assertEqual(award, Type(<<"dir-awa-pre">>, none)).

%% A contract modification and a completion are about contracts long since
%% awarded; they are none of the four kinds a company is told about.
other_forms_are_not_reported_test() ->
    ?assertEqual({skip, {form_type, <<"cont-modif">>}},
                 parse_ted_notice:parse(?NOTICE(#{<<"form-type">> => <<"cont-modif">>}))),
    ?assertEqual({skip, {form_type, <<"completion">>}},
                 parse_ted_notice:parse(?NOTICE(#{<<"form-type">> => <<"completion">>}))),
    ?assertEqual({skip, {form_type, none}},
                 parse_ted_notice:parse(maps:remove(<<"form-type">>, ?NOTICE))).

%% T4, the sensor's half: the company node rebuilds the TED link from the
%% publication number, so a number not in TED's form is never reported.
a_malformed_publication_number_is_not_reported_test() ->
    [?assertEqual({skip, publication_number},
                  parse_ted_notice:parse(?NOTICE(#{<<"publication-number">> => Bad})))
     || Bad <- [<<"745687-26">>, <<"../745687-2026">>, <<"745687-2026?x=1">>,
                <<"123456789-2026">>, <<>>, 42]],
    ?assertEqual({skip, publication_number},
                 parse_ted_notice:parse(maps:remove(<<"publication-number">>, ?NOTICE))).

%% The company node keys its matches on the procedure id, so only a plain id
%% is carried; a notice without one (a prior information notice) carries none.
the_procedure_id_is_plain_or_empty_test() ->
    Weird = parse(?NOTICE(#{<<"procedure-identifier">> => <<"a/../b">>})),
    ?assertEqual(<<>>, maps:get(procedure_id, Weird)),
    ?assertEqual(<<>>, maps:get(procedure_id, parse(maps:remove(<<"procedure-identifier">>, ?NOTICE)))).

%% New fields, missing fields and fields of another type must not stop a
%% sweep: the field list is outside TED's API versioning.
an_odd_notice_still_parses_test() ->
    Odd = #{<<"publication-number">> => <<"1-2026">>, <<"form-type">> => <<"competition">>,
            <<"buyer-name">> => <<"Plain name">>, <<"buyer-country">> => <<"bel">>,
            <<"classification-cpv">> => <<"72000000">>, <<"notice-title">> => null,
            <<"description-proc">> => #{<<"fra">> => [<<"Un">>, <<"deux">>]},
            <<"a-field-from-next-year">> => #{<<"x">> => 1}},
    N = parse(Odd),
    ?assertEqual(<<"Plain name">>, maps:get(buyer_name, N)),
    ?assertEqual(<<"BEL">>, maps:get(buyer_country, N)),
    ?assertEqual([<<"72000000">>], maps:get(cpv_codes, N)),
    ?assertEqual(#{}, maps:get(titles, N)),
    ?assertEqual({<<"Un deux">>, <<"fra">>}, {maps:get(description, N), maps:get(description_lang, N)}).

%% A5 starts here: the sensor never ASKS TED for a contact field, so none can
%% reach a fact even through a parser bug.
the_sensor_asks_for_no_contact_field_test() ->
    Fields = parse_ted_notice:fields(),
    ?assertEqual([], [F || F <- Fields, contact_field(F)]),
    ?assertNot(lists:member(<<"links">>, Fields)).

contact_field(F) ->
    lists:any(fun(Word) -> binary:match(F, Word) =/= nomatch end,
              [<<"email">>, <<"phone">>, <<"fax">>, <<"touchpoint">>, <<"contact">>,
               <<"url">>, <<"internet">>, <<"post-code">>, <<"street">>, <<"winner">>]).

with_change(Notice, none) -> Notice;
with_change(Notice, Change) -> Notice#{<<"change-notice-version-identifier">> => Change}.

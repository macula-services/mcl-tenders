%%% @doc One TED Search API notice into the one map the fact is built from.
%%%
%%% The Search API (v3) answers eForms notices and the older TED-schema ones in
%%% one JSON shape, so this is the only reader the sensor needs. Its field list
%%% is outside the API's versioning and can change without a new version
%%% (https://docs.ted.europa.eu/api/latest/index.html), so every field is read
%%% defensively: a missing field or one of another type gives an empty value,
%%% never a crash, and an unknown field is ignored.
%%%
%%% A CLOSED LIST, BOTH WAYS (A5 of the design's threat model). fields/0 is
%%% everything the sensor asks TED for, and it names no contact field: TED's
%%% legal notice says contact details "in some cases contain personal data",
%%% and a company reads those on TED itself, through the link its own node
%%% rebuilds. parse/1 reads only the fields it names, so a contact field TED
%%% sends anyway goes nowhere.
-module(parse_ted_notice).

-export([parse/1, fields/0, publication_day/1]).

-export_type([notice/0, notice_type/0]).

-type notice_type() :: contract_notice | prior_information | correction | award.
-type notice() :: #{publication_number := binary(), procedure_id := binary(),
                    notice_type := notice_type(), buyer_name := binary(),
                    buyer_country := binary(), cpv_codes := [binary()],
                    titles := #{binary() => binary()}, description := binary(),
                    description_lang := binary(), deadline_at := non_neg_integer(),
                    estimated_value := binary(), currency := binary(),
                    published_at := non_neg_integer(), source := ted}.

%% TED's own form: a serial and a year, "745687-2026". The company node rebuilds
%% the notice's link from this alone (T4), so nothing else gets through.
-define(PUBLICATION_NUMBER, "^[0-9]{1,8}-[0-9]{4}$").
-define(PROCEDURE_ID, "^[0-9A-Za-z-]{1,64}$").
-define(CPV, "^[0-9]{8}$").
-define(DECIMAL, "^[0-9]{1,15}(\\.[0-9]{1,4})?$").
-define(CURRENCY, "^[A-Z]{3}$").
-define(DATE, "^([0-9]{4}-[0-9]{2}-[0-9]{2})(Z|[+-][0-9]{2}:[0-9]{2})?$").
-define(TIME, "^([0-9]{2}:[0-9]{2}:[0-9]{2})(Z|[+-][0-9]{2}:[0-9]{2})?$").

%% @doc Every field the sensor asks TED for, and nothing else.
-spec fields() -> [binary()].
fields() ->
    [<<"publication-number">>, <<"procedure-identifier">>, <<"form-type">>,
     <<"notice-type">>, <<"change-notice-version-identifier">>, <<"buyer-name">>,
     <<"buyer-country">>, <<"classification-cpv">>, <<"official-language">>,
     <<"notice-title">>, <<"description-proc">>, <<"deadline-receipt-tender-date-lot">>,
     <<"deadline-receipt-tender-time-lot">>, <<"estimated-value-proc">>,
     <<"estimated-value-cur-proc">>, <<"publication-date">>].

%% @doc The notice, or why it is not reported: a publication number not in
%% TED's form, or a form that is none of the four kinds a company is told about.
-spec parse(map()) -> {ok, notice()} | {skip, publication_number | {form_type, binary() | none}}.
parse(Json) ->
    numbered(matches(field(<<"publication-number">>, Json), ?PUBLICATION_NUMBER), Json).

numbered(false, _Json) -> {skip, publication_number};
numbered(true, Json) -> typed(notice_type(form_type(Json), changes(Json)), Json).

typed({skip, _} = Skip, _Json) -> Skip;
typed(Type, Json) -> {ok, notice(Type, Json)}.

notice(Type, Json) ->
    Langs = official_languages(Json),
    {Description, DescriptionLang} = description(field(<<"description-proc">>, Json), Langs),
    Value = only(first(field(<<"estimated-value-proc">>, Json)), ?DECIMAL),
    #{publication_number => field(<<"publication-number">>, Json),
      procedure_id => only(first(field(<<"procedure-identifier">>, Json)), ?PROCEDURE_ID),
      notice_type => Type,
      buyer_name => in_language(field(<<"buyer-name">>, Json), Langs),
      buyer_country => string:uppercase(first(field(<<"buyer-country">>, Json))),
      cpv_codes => cpv_codes(field(<<"classification-cpv">>, Json)),
      titles => titles(field(<<"notice-title">>, Json), Langs),
      description => Description,
      description_lang => DescriptionLang,
      deadline_at => deadline(field(<<"deadline-receipt-tender-date-lot">>, Json),
                              field(<<"deadline-receipt-tender-time-lot">>, Json)),
      estimated_value => Value,
      currency => currency(Value, first(field(<<"estimated-value-cur-proc">>, Json))),
      published_at => instant(first(field(<<"publication-date">>, Json)), <<>>),
      source => ted}.

%% @doc The OJ S day a notice was published on, as TED writes it, or none.
%% The calendar day TED names, not the UTC day of its instant: "2026-10-28+01:00"
%% is the 28th, though it began at 23:00 UTC on the 27th.
-spec publication_day(map()) -> calendar:date() | none.
publication_day(Json) ->
    valid_day(re:run(first(field(<<"publication-date">>, Json)), ?DATE,
                     [{capture, all_but_first, list}])).

valid_day({match, [[Y1, Y2, Y3, Y4, $-, M1, M2, $-, D1, D2] | _]}) ->
    Day = {list_to_integer([Y1, Y2, Y3, Y4]), list_to_integer([M1, M2]), list_to_integer([D1, D2])},
    real_day(calendar:valid_date(Day), Day);
valid_day(_NoDay) ->
    none.

real_day(true, Day) -> Day;
real_day(false, _Day) -> none.

%%------------------------------------------------------------------------------
%% Which kind of notice
%%------------------------------------------------------------------------------

%% eForms has no correction form: a correction is a notice that names the notice
%% it changes. An award stays an award when it corrects an earlier one.
notice_type(<<"competition">>, false) -> contract_notice;
notice_type(<<"competition">>, true) -> correction;
notice_type(<<"planning">>, false) -> prior_information;
notice_type(<<"consultation">>, false) -> prior_information;
notice_type(<<"planning">>, true) -> correction;
notice_type(<<"consultation">>, true) -> correction;
notice_type(<<"result">>, _Changes) -> award;
notice_type(<<"dir-awa-pre">>, _Changes) -> award;
notice_type(Other, _Changes) -> {skip, {form_type, Other}}.

form_type(Json) -> named(first(field(<<"form-type">>, Json))).

named(<<>>) -> none;
named(Form) -> Form.

changes(Json) -> first(field(<<"change-notice-version-identifier">>, Json)) =/= <<>>.

%%------------------------------------------------------------------------------
%% Text in languages
%%------------------------------------------------------------------------------

%% TED names languages two ways: "NLD" in official-language, "nld" as the key of
%% a text map. Both become the lower-case form.
official_languages(Json) ->
    [string:lowercase(L) || L <- list(field(<<"official-language">>, Json)), is_binary(L)].

%% The title in each language the buyer published in, plus English: TED
%% machine-translates the label part into all 24, and 24 copies of a title per
%% notice is not what a company node needs to match on. A notice with none of
%% those keeps the titles it has.
titles(Titles, Langs) when is_map(Titles) ->
    Text = maps:filtermap(fun(_L, T) -> text_of(T) end, Titles),
    preferred(maps:with([<<"eng">> | Langs], Text), Text);
titles(_NotAMap, _Langs) ->
    #{}.

preferred(Some, _All) when map_size(Some) > 0 -> Some;
preferred(_None, All) -> All.

%% The buyer's own description, in the language they wrote it in.
description(Texts, Langs) when is_map(Texts), map_size(Texts) > 0 ->
    Lang = pick_language(Langs, Texts),
    {joined(maps:get(Lang, Texts)), Lang};
description(_None, _Langs) ->
    {<<>>, <<>>}.

in_language(Texts, Langs) when is_map(Texts), map_size(Texts) > 0 ->
    first(maps:get(pick_language(Langs, Texts), Texts));
in_language(Text, _Langs) ->
    first(Text).

pick_language(Langs, Texts) ->
    hd([L || L <- Langs, maps:is_key(L, Texts)] ++ lists:sort(maps:keys(Texts))).

text_of(T) ->
    present(joined(T)).

present(<<>>) -> false;
present(T) -> {true, T}.

joined(T) when is_binary(T) -> T;
joined(Ts) when is_list(Ts) -> iolist_to_binary(lists:join(<<" ">>, [T || T <- Ts, is_binary(T)]));
joined(_Other) -> <<>>.

%%------------------------------------------------------------------------------
%% Codes, values, dates
%%------------------------------------------------------------------------------

%% TED repeats a code once per lot: each is kept once, first seen first.
cpv_codes(Codes) ->
    dedupe([C || C <- list(Codes), is_binary(C), matches(C, ?CPV)], #{}, []).

dedupe([], _Seen, Acc) -> lists:reverse(Acc);
dedupe([C | Rest], Seen, Acc) when is_map_key(C, Seen) -> dedupe(Rest, Seen, Acc);
dedupe([C | Rest], Seen, Acc) -> dedupe(Rest, Seen#{C => true}, [C | Acc]).

currency(<<>>, _Currency) -> <<>>;
currency(_Value, Currency) -> only(Currency, ?CURRENCY).

%% The earliest lot's deadline, date and time together. A lot without a time
%% reads as the start of its day: a company is told earlier, never later.
deadline(Dates, Times) ->
    Ds = list(Dates),
    Ts = list(Times) ++ lists:duplicate(length(Ds), <<>>),
    earliest([I || {D, T} <- lists:zip(Ds, lists:sublist(Ts, length(Ds))),
                   I <- [instant(D, T)], I > 0]).

earliest([]) -> 0;
earliest(Instants) -> lists:min(Instants).

%% "2026-11-17+01:00" with "10:00:00+01:00", as ms since the epoch; 0 when the
%% date cannot be read. The time's own offset wins when it has one.
instant(Date, Time) ->
    date_time(re:run(text(Date), ?DATE, [{capture, all_but_first, list}]),
              re:run(text(Time), ?TIME, [{capture, all_but_first, list}])).

date_time({match, [Day | DateOffset]}, nomatch) ->
    rfc3339(Day, "00:00:00", offset(DateOffset));
date_time({match, [Day | DateOffset]}, {match, [Clock | TimeOffset]}) ->
    rfc3339(Day, Clock, offset(TimeOffset ++ DateOffset));
date_time(nomatch, _Time) ->
    0.

offset([]) -> "Z";
offset([Offset | _]) -> Offset.

rfc3339(Day, Clock, Offset) ->
    try calendar:rfc3339_to_system_time(Day ++ "T" ++ Clock ++ Offset, [{unit, millisecond}]) of
        Ms when Ms > 0 -> Ms;
        _BeforeTheEpoch -> 0
    catch
        error:_ -> 0
    end.

%%------------------------------------------------------------------------------

field(Name, Json) -> maps:get(Name, Json, <<>>).

list(L) when is_list(L) -> L;
list(<<>>) -> [];
list(One) -> [One].

first([H | _]) -> text(H);
first(Other) -> text(Other).

text(B) when is_binary(B) -> B;
text(_NotText) -> <<>>.

only(Value, Pattern) -> kept(matches(Value, Pattern), Value).

kept(true, Value) -> Value;
kept(false, _Value) -> <<>>.

matches(Value, Pattern) when is_binary(Value) -> re:run(Value, Pattern, [{capture, none}]) =:= match;
matches(_NotText, _Pattern) -> false.

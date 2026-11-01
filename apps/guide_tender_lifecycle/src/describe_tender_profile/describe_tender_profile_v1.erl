%%% @doc Command `describe_tender_profile_v1'.
%%%
%%% What the realm looks for in a public tender. It replaces the whole previous
%%% description.
%%%
%%%   - `cpv_codes': up to 100 CPV codes, each eight digits, the form TED
%%%     searches by. The sensor puts them in its query to TED (T3), so they are
%%%     codes and nothing else (T6).
%%%   - `countries': up to 40 ISO 3166-1 alpha-3 codes in capitals, as TED
%%%     names a buyer's country ("BEL"); also in the query to TED.
%%%   - `keywords' and `exclusions': up to 50 each, 1 to 100 NFC bytes, text as
%%%     tender_profile_text allows it. They never leave the node.
%%%   - `description': 0 to 4000 NFC bytes, lines allowed. Never leaves the node.
%%%
%%% Codes are sorted and deduplicated. `described_by' is the caller's node id,
%%% kept so the realm can see who last changed what it bids for.
%%% @end
-module(describe_tender_profile_v1).
-behaviour(evoq_command).

-export([command_type/0]).
-export([new/1, from_map/1, validate/1, to_map/1]).
-export([stream_id/1, get_realm/1, fields/1]).

-define(CPV, "^[0-9]{8}\\z").
-define(COUNTRY, "^[A-Z]{3}\\z").

-record(describe_tender_profile_v1, {
    realm :: <<_:256>>,
    described_by :: <<_:256>>,
    cpv_codes :: [binary()],
    countries :: [binary()],
    keywords :: [binary()],
    exclusions :: [binary()],
    description :: binary()
}).

-opaque t() :: #describe_tender_profile_v1{}.
-export_type([t/0]).

-spec command_type() -> atom().
command_type() -> describe_tender_profile_v1.

%% @doc A command that exists is a valid one, its text already normalised.
-spec new(map()) -> {ok, t()} | {error, atom()}.
new(#{realm := <<_:256>> = Realm} = Params) ->
    by_member(maps:get(described_by, Params, undefined), Realm, Params);
new(_) ->
    {error, invalid_realm}.

%% @doc Rebuilds a command already validated by new/1, as evoq hands it back.
-spec from_map(map()) -> {ok, t()} | {error, term()}.
from_map(#{realm := <<_:256>> = Realm, described_by := <<_:256>> = By, cpv_codes := Cpv,
           countries := Countries, keywords := Keywords, exclusions := Exclusions,
           description := Description})
  when is_list(Cpv), is_list(Countries), is_list(Keywords), is_list(Exclusions),
       is_binary(Description) ->
    {ok, #describe_tender_profile_v1{realm = Realm, described_by = By, cpv_codes = Cpv,
                                     countries = Countries, keywords = Keywords,
                                     exclusions = Exclusions, description = Description}};
from_map(_) ->
    {error, invalid_tender_profile_description}.

-spec validate(t()) -> ok | {error, term()}.
validate(#describe_tender_profile_v1{}) -> ok.

-spec to_map(t()) -> map().
to_map(#describe_tender_profile_v1{realm = Realm, described_by = By} = Cmd) ->
    maps:merge(#{command_type => describe_tender_profile_v1, realm => Realm, described_by => By},
               fields(Cmd)).

-spec stream_id(t()) -> binary().
stream_id(#describe_tender_profile_v1{realm = Realm}) ->
    tender_profile_aggregate:stream_id(Realm).

-spec get_realm(t()) -> <<_:256>>.
get_realm(#describe_tender_profile_v1{realm = V}) -> V.

%% @doc The described fields, as the event carries them.
-spec fields(t()) -> map().
fields(#describe_tender_profile_v1{cpv_codes = Cpv, countries = Countries, keywords = Keywords,
                                   exclusions = Exclusions, description = Description}) ->
    #{cpv_codes => Cpv, countries => Countries, keywords => Keywords,
      exclusions => Exclusions, description => Description}.

%%--------------------------------------------------------------------
%% Checking the fields
%%--------------------------------------------------------------------

by_member(<<_:256>> = By, Realm, Params) ->
    built(Realm, By, [{Field, Refusal, Check(maps:get(Field, Params, Default))}
                      || {Field, Default, Check, Refusal} <- rules()]);
by_member(_Missing, _Realm, _Params) ->
    {error, no_caller}.

%% Field, its default when absent, its check, and the refusal naming it.
rules() ->
    [{cpv_codes, [], fun(V) -> listed(V, 100, code(?CPV)) end, invalid_cpv_codes},
     {countries, [], fun(V) -> listed(V, 40, code(?COUNTRY)) end, invalid_countries},
     {keywords, [], fun(V) -> listed(V, 50, term()) end, invalid_keywords},
     {exclusions, [], fun(V) -> listed(V, 50, term()) end, invalid_exclusions},
     {description, <<>>, fun(V) -> tender_profile_text:checked(V, 0, 4000, lines) end,
      invalid_description}].

built(Realm, By, Checked) ->
    first_refusal([Refusal || {_Field, Refusal, error} <- Checked], Realm, By,
                  maps:from_list([{Field, V} || {Field, _Refusal, {ok, V}} <- Checked])).

first_refusal([Refusal | _], _Realm, _By, _Fields) ->
    {error, Refusal};
first_refusal([], Realm, By, #{cpv_codes := Cpv, countries := Countries, keywords := Keywords,
                               exclusions := Exclusions, description := Description}) ->
    {ok, #describe_tender_profile_v1{realm = Realm, described_by = By,
                                     cpv_codes = lists:usort(Cpv),
                                     countries = lists:usort(Countries),
                                     keywords = Keywords, exclusions = Exclusions,
                                     description = Description}}.

listed(List, Max, Check) when is_list(List), length(List) =< Max ->
    every([Check(Item) || Item <- List]);
listed(_NotAList, _Max, _Check) ->
    error.

every(Checked) ->
    all_ok(lists:all(fun({ok, _}) -> true; (error) -> false end, Checked), Checked).

all_ok(true, Checked) -> {ok, [V || {ok, V} <- Checked]};
all_ok(false, _Checked) -> error.

code(Pattern) ->
    fun(Code) when is_binary(Code) -> matched(re:run(Code, Pattern, [{capture, none}]), Code);
       (_NotText) -> error
    end.

matched(match, Code) -> {ok, Code};
matched(nomatch, _Code) -> error.

term() ->
    fun(Text) -> tender_profile_text:checked(Text, 1, 100, line) end.

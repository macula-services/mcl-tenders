%%% @doc Whether a notice fits the realm's profile, and why.
%%%
%%% In order, every rule on the node, in process (T1):
%%%
%%%   1. the buyer's country is one of the profile's countries;
%%%   2. a notice CPV code falls under a profile code. CPV is a hierarchy,
%%%      written as eight digits with trailing zeros for the levels above, so
%%%      `72000000' covers `72315000'; a code covers what shares its digits
%%%      before the trailing zeros (at least two, the division);
%%%   3. no exclusion term appears in a title or the description;
%%%   4. a keyword appears in a title or the description. A profile with no
%%%      keywords fits on its codes and countries alone.
%%%
%%% TED already narrowed the notices to the profile's codes and countries;
%%% rules 1 and 2 are checked again, because a profile can change between a
%%% sweep and the fact's arrival.
%%%
%%% THIS IS THE KEYWORD FIT ONLY (#4a). Similarity to the profile's
%%% description, computed in process, is #4c; until then the description
%%% plays no part in the fit.
%%%
%%% Terms are matched case-insensitively (Unicode case folding) on NFC text,
%%% as substrings: `bouw' finds `Bouwwerken'.
%%% @end
-module(tender_fit).

-export([fit/2, covers/2]).

-type reasons() :: #{matched_cpv_codes := [binary()], matched_keywords := [binary()]}.
-export_type([reasons/0]).

%% @doc Fit, with the profile codes and keywords that matched, or the first
%% rule the notice failed.
-spec fit(tender_notice:notice(), get_tender_profile:profile()) ->
          {fits, reasons()} | {no_fit, country | cpv_code | exclusion | keyword}.
fit(Notice, Profile) ->
    country(lists:member(maps:get(buyer_country, Notice), maps:get(countries, Profile)),
            Notice, Profile).

%% @doc Whether profile code `Code' covers notice code `Of'.
-spec covers(binary(), binary()) -> boolean().
covers(Code, Of) ->
    Prefix = significant(Code),
    binary:longest_common_prefix([Prefix, Of]) =:= byte_size(Prefix).

country(false, _Notice, _Profile) -> {no_fit, country};
country(true, Notice, #{cpv_codes := Codes} = Profile) ->
    coded([C || C <- Codes, lists:any(fun(Of) -> covers(C, Of) end, maps:get(cpv_codes, Notice))],
          folded(Notice), Profile).

coded([], _Text, _Profile) -> {no_fit, cpv_code};
coded(Codes, Text, #{exclusions := Exclusions} = Profile) ->
    excluded(found(Exclusions, Text), Codes, Text, Profile).

excluded([_ | _], _Codes, _Text, _Profile) -> {no_fit, exclusion};
excluded([], Codes, _Text, #{keywords := []}) ->
    {fits, #{matched_cpv_codes => Codes, matched_keywords => []}};
excluded([], Codes, Text, #{keywords := Keywords}) ->
    keyed(found(Keywords, Text), Codes).

keyed([], _Codes) -> {no_fit, keyword};
keyed(Hits, Codes) -> {fits, #{matched_cpv_codes => Codes, matched_keywords => Hits}}.

found(Terms, Text) ->
    [T || T <- Terms, binary:match(Text, fold(T)) =/= nomatch].

%% Every title and the description, folded once, newline-joined so a term
%% never matches across two of them.
folded(#{titles := Titles, description := Description}) ->
    fold(iolist_to_binary(lists:join(<<"\n">>, maps:values(Titles) ++ [Description]))).

fold(Text) ->
    unicode:characters_to_binary(string:casefold(unicode:characters_to_nfc_binary(Text))).

significant(Code) ->
    Stripped = string:trim(Code, trailing, "0"),
    binary:part(Code, 0, max(2, byte_size(Stripped))).

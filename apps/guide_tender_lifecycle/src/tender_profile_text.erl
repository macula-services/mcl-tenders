%%% @doc What text a tenders profile may carry.
%%%
%%% Keywords and exclusions are matched against notice text, and shown back to
%%% the bid team, which is where an invisibly padded or reversed term would
%%% match nothing or mislead. So text is normalised to NFC first (lengths count
%%% the normalised bytes), and refused when it is not UTF-8 or carries a
%%% character of one of these Unicode general categories: Cc (control: C0,
%%% DEL, C1), Cf (format: bidi embeddings, overrides and isolates, zero-width
%%% spaces and joiners, the BOM, the soft hyphen, the tag block, the
%%% interlinear annotation marks and every other invisible format character),
%%% Zl and Zp (line and paragraph separators), and Cn (unassigned, which no
%%% term needs and a future version may give a meaning). The set is the
%%% categories as OTP's regular expressions know them, not a list kept by hand.
%%%
%%% `lines' allows one control character, the line feed, for the description.
%%% @end
-module(tender_profile_text).

-export([checked/4]).

%% @doc The NFC form of Text when it is acceptable and Min to Max bytes long.
-spec checked(term(), non_neg_integer(), pos_integer(), line | lines) -> {ok, binary()} | error.
checked(Text, Min, Max, Lines) when is_binary(Text) ->
    sized(normalised(unicode:characters_to_nfc_binary(Text), Lines), Min, Max);
checked(_Other, _Min, _Max, _Lines) ->
    error.

normalised(Nfc, Lines) when is_binary(Nfc) ->
    plain(re:run(Nfc, refused(Lines), [unicode, ucp, {capture, none}]), Nfc);
normalised(_Malformed, _Lines) ->
    error.

plain(nomatch, Nfc) -> {ok, Nfc};
plain(match, _Nfc) -> error.

sized({ok, Nfc}, Min, Max) when byte_size(Nfc) >= Min, byte_size(Nfc) =< Max -> {ok, Nfc};
sized(_, _Min, _Max) -> error.

refused(line) -> <<"[\\p{Cc}\\p{Cf}\\p{Zl}\\p{Zp}\\p{Cn}]">>;
refused(lines) -> <<"[^\\n\\P{Cc}]|[\\p{Cf}\\p{Zl}\\p{Zp}\\p{Cn}]">>.

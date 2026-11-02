%%% @doc A TED notice as the dossier keeps it: read from one
%%% `tender_notice_reported_v1' fact, every field checked again.
%%%
%%% The fact comes from the realm's own sensor (sources: the realm's
%%% `mcl-tenders' org, T4), and the dossier still trusts none of its text:
%%% a publication number not in TED's form drops the notice, because the TED
%%% link is rebuilt from it alone (T4); a code that is not a code is dropped;
%%% text is bounded again, so a fact can never make a dossier large (T6). The
%%% field list is the fact's own (mcl_tenders_facts:fields/0) and closed.
%%% @end
-module(tender_notice).

-export([from_fact/1, tender_id/1, valid_tender_id/1, fields/0]).

-define(PUBLICATION_NUMBER, "^[0-9]{1,8}-[0-9]{4}\\z").
-define(TENDER_ID, "^[0-9A-Za-z-]{1,64}\\z").
-define(CPV, "^[0-9]{8}\\z").
-define(COUNTRY, "^[A-Z]{3}\\z").
-define(LANGUAGE, "^[a-z]{3}\\z").
-define(DECIMAL, "^[0-9]{1,15}(\\.[0-9]{1,4})?\\z").
-define(TYPES, [<<"contract_notice">>, <<"prior_information">>, <<"correction">>, <<"award">>]).
%% Bytes, a little above the sensor's grapheme bounds, so a fact the sensor
%% built always fits and nothing else ever grows past them.
-define(TITLE_MAX, 1600).
-define(DESCRIPTION_MAX, 6000).
-define(NAME_MAX, 1600).
-define(MAX_TITLES, 6).
-define(MAX_CPV_CODES, 100).

-type notice() :: #{publication_number := binary(), procedure_id := binary(),
                    notice_type := binary(), buyer_name := binary(),
                    buyer_country := binary(), cpv_codes := [binary()],
                    titles := #{binary() => binary()}, description := binary(),
                    description_lang := binary(), deadline_at := non_neg_integer(),
                    estimated_value := binary(), currency := binary(),
                    published_at := non_neg_integer(), source := binary()}.
-export_type([notice/0]).

%% @doc The fields a notice carries, the fact's own.
-spec fields() -> [atom()].
fields() ->
    [publication_number, procedure_id, notice_type, buyer_name, buyer_country,
     cpv_codes, titles, description, description_lang, deadline_at,
     estimated_value, currency, published_at, source].

%% @doc The notice in one fact's payload, or why it is dropped.
-spec from_fact(map()) -> {ok, notice()} | {skip, publication_number | notice_type}.
from_fact(Payload) when is_map(Payload) ->
    numbered(code(field(publication_number, Payload), ?PUBLICATION_NUMBER), Payload);
from_fact(_NotAMap) ->
    {skip, publication_number}.

%% @doc The dossier a notice belongs to: its procedure, or the notice itself
%% when TED names no procedure.
-spec tender_id(notice()) -> binary().
tender_id(#{procedure_id := <<>>, publication_number := Number}) -> Number;
tender_id(#{procedure_id := Id}) -> Id.

%% @doc Whether an id a caller sends could name a dossier at all.
-spec valid_tender_id(term()) -> boolean().
valid_tender_id(Id) when is_binary(Id) -> code(Id, ?TENDER_ID) =/= <<>>;
valid_tender_id(_) -> false.

%%------------------------------------------------------------------------------

numbered(<<>>, _Payload) -> {skip, publication_number};
numbered(Number, Payload) -> typed(lists:member(field(notice_type, Payload), ?TYPES), Number, Payload).

typed(false, _Number, _Payload) -> {skip, notice_type};
typed(true, Number, Payload) ->
    {ok, #{publication_number => Number,
           procedure_id => code(field(procedure_id, Payload), ?TENDER_ID),
           notice_type => field(notice_type, Payload),
           buyer_name => bounded(field(buyer_name, Payload), ?NAME_MAX),
           buyer_country => code(field(buyer_country, Payload), ?COUNTRY),
           cpv_codes => cpv_codes(mcl_om_wire:field(cpv_codes, Payload, [])),
           titles => titles(mcl_om_wire:field(titles, Payload, #{})),
           description => bounded(field(description, Payload), ?DESCRIPTION_MAX),
           description_lang => code(field(description_lang, Payload), ?LANGUAGE),
           deadline_at => count(mcl_om_wire:field(deadline_at, Payload, 0)),
           estimated_value => code(field(estimated_value, Payload), ?DECIMAL),
           currency => code(field(currency, Payload), ?COUNTRY),
           published_at => count(mcl_om_wire:field(published_at, Payload, 0)),
           source => source(field(source, Payload))}}.

field(Key, Payload) -> text(mcl_om_wire:field(Key, Payload, <<>>)).

%% A map's keys come off the wire still wrapped (mcl_om_wire unwraps values).
text(Bin) when is_binary(Bin) -> Bin;
text({text, Bin}) when is_binary(Bin) -> Bin;
text(_NotText) -> <<>>.

code(Bin, Pattern) -> coded(re:run(Bin, Pattern, [{capture, none}]), Bin).

coded(match, Bin) -> Bin;
coded(nomatch, _Bin) -> <<>>.

cpv_codes(Codes) when is_list(Codes) ->
    lists:usort([C || C <- [code(text(Code), ?CPV) || Code <- lists:sublist(Codes, ?MAX_CPV_CODES)],
                      C =/= <<>>]);
cpv_codes(_NotAList) ->
    [].

titles(Titles) when is_map(Titles) ->
    Kept = [{code(text(L), ?LANGUAGE), bounded(text(T), ?TITLE_MAX)} || {L, T} <- maps:to_list(Titles)],
    maps:from_list(lists:sublist(lists:sort([LT || {L, _} = LT <- Kept, L =/= <<>>]), ?MAX_TITLES));
titles(_NotAMap) ->
    #{}.

%% Valid UTF-8 within the bound, or nothing: a fact never grows a dossier.
bounded(Bin, Max) when byte_size(Bin) =< Max -> utf8(unicode:characters_to_binary(Bin), Bin);
bounded(_TooLong, _Max) -> <<>>.

utf8(Bin, Bin) -> Bin;
utf8(_Invalid, _Bin) -> <<>>.

count(N) when is_integer(N), N >= 0 -> N;
count(_NotACount) -> 0.

source(<<"ted">>) -> <<"ted">>;
source(_Other) -> <<"ted">>.

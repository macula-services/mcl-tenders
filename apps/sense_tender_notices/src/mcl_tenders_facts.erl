%%% @doc The contract of mcl-tenders' one fact, and nothing else leaves the
%%% sensor.
%%%
%%%   tender_notice_reported_v1   TED published a notice in the realm's CPV
%%%                               codes and countries that this sensor had not
%%%                               reported before
%%%
%%% The topic is a canonical macula app fact owned by org `mcl-tenders', app
%%% `tenders', domain `wire': `<realm name>/mcl-tenders/tenders/wire/
%%% tender_notice_reported_v1'. The org segment is the schema owner and is fixed
%%% here, not deploy config. The sensor and guide_tender_lifecycle build against
%%% this one module, so a change to it is one change to both.
%%%
%%% INSIDE THE REALM, SEALED (T3 of the threat model, as amended). The sensor
%%% asks TED for the profile's codes and countries, so its facts are the
%%% realm's matches: every one is sealed under the realm's tenders group
%%% (tender_notices_group), and the stations see traffic, never a payload.
%%%
%%% ONE TOPIC FOR EVERY NOTICE. Country, CPV code and notice type are payload
%%% fields. A topic per code would show every station which codes the realm
%%% follows; one sealed topic shows them nothing but traffic.
%%%
%%% EVERYTHING THE MATCHING NEEDS, SO NOBODY ASKS. The sensor serves no
%%% procedure: the fact carries what guide_tender_lifecycle matches on.
%%%
%%% A CLOSED FIELD LIST (A5, T4). fact/1 reads only fields/0 from the notice:
%%% no contact data, and no url. The TED link is rebuilt from the publication
%%% number, so a link in a payload can never be followed.
%%%
%%% WHO REPORTED IT IS NOT IN THE PAYLOAD. macula delivers every event with the
%%% publisher its link verified, and the subscriber names the realm's
%%% `mcl-tenders' org as its sources (T4).
%%%
%%% Every string is `{text, Bin}' (CBOR text), so consumers outside the BEAM get
%%% strings and not hex, and there is no boolean anywhere.
-module(mcl_tenders_facts).

-export([report/1, topic/1, fact/1, fields/0,
         realm_name/0, check_realm_name/0, check_realm_name/2]).

-define(APP, sense_tender_notices).
%% Graphemes. T6: notice text reaches a company's agent as data, so it is
%% bounded; and a fact stays a few kilobytes whatever TED sends.
-define(TITLE_MAX, 300).
-define(DESCRIPTION_MAX, 1200).
-define(NAME_MAX, 300).
-define(MAX_TITLES, 6).
-define(MAX_CPV_CODES, 100).

%% @doc Publish one notice, sealed under the realm's tenders group, and answer
%% how it went. Synchronous, so the sweep marks a notice reported only once it
%% was: a dark mesh, a refused publish or a key the distributor would not hand
%% over answers an error, and the next sweep tries the notice again.
-spec report(parse_ted_notice:notice()) -> ok | {error, term()}.
report(Notice) ->
    RealmName = realm_name(),
    mcl_om_pubsub:publish(topic(RealmName), fact(Notice),
                          tender_notices_group:publish_opts(RealmName, #{mode => sync})).

-spec topic(binary()) -> binary().
topic(RealmName) ->
    macula_topic:app_fact(RealmName, <<"mcl-tenders">>, <<"tenders">>, <<"wire">>,
                          <<"tender_notice_reported">>, 1).

%% @doc The fields every fact carries: the whole contract.
-spec fields() -> [atom()].
fields() ->
    [publication_number, procedure_id, notice_type, buyer_name, buyer_country,
     cpv_codes, titles, description, description_lang, deadline_at,
     estimated_value, currency, published_at, source].

%% @doc The fact for one parsed notice, built from fields/0 alone.
-spec fact(parse_ted_notice:notice()) -> map().
fact(Notice) ->
    #{publication_number => text(field(publication_number, Notice)),
      procedure_id => text(field(procedure_id, Notice)),
      notice_type => text(atom_to_binary(maps:get(notice_type, Notice))),
      buyer_name => free_text(field(buyer_name, Notice), ?NAME_MAX),
      buyer_country => text(field(buyer_country, Notice)),
      cpv_codes => [text(C) || C <- lists:sublist(maps:get(cpv_codes, Notice, []), ?MAX_CPV_CODES)],
      titles => titles(maps:get(titles, Notice, #{})),
      description => free_text(field(description, Notice), ?DESCRIPTION_MAX),
      description_lang => text(field(description_lang, Notice)),
      deadline_at => integer(maps:get(deadline_at, Notice, 0)),
      estimated_value => text(field(estimated_value, Notice)),
      currency => text(field(currency, Notice)),
      published_at => integer(maps:get(published_at, Notice, 0)),
      source => text(atom_to_binary(maps:get(source, Notice, ted)))}.

%% @doc The realm name the topic carries, from `MCL_REALM_NAME'.
-spec realm_name() -> binary().
realm_name() ->
    named(application:get_env(?APP, realm_name, undefined)).

named(Name) when is_list(Name), Name =/= "" -> unicode:characters_to_binary(Name);
named(Name) when is_binary(Name), Name =/= <<>> -> Name;
named(_Unset) -> error({mcl_tenders_realm_name_unset, realm_name}).

%% @doc Refuse to start when the realm name is not the realm the pool publishes
%% in: the facts would go where nobody subscribed, and a sensor reporting into
%% nothing looks exactly like a quiet day at TED.
-spec check_realm_name() -> ok.
check_realm_name() ->
    configured(realm_name(), mcl_om:realm()).

configured(Name, {ok, Tag}) -> check_realm_name(Name, Tag);
configured(Name, Other) -> error({mcl_tenders_realm_unset, Name, Other}).

%% The topic is built here too: a name that hashes right but is not a valid
%% topic segment would pass the hash and then fail every report.
-spec check_realm_name(binary(), binary()) -> ok.
check_realm_name(Name, Tag) ->
    _ = topic(Name),
    matched(crypto:hash(sha256, Name) =:= Tag, Name, Tag).

matched(true, _Name, _Tag) -> ok;
matched(false, Name, Tag) -> error({mcl_tenders_realm_name_mismatch, Name, Tag}).

%%------------------------------------------------------------------------------

titles(Titles) when is_map(Titles) ->
    Kept = lists:sublist(lists:sort(maps:to_list(Titles)), ?MAX_TITLES),
    maps:from_list([{text(binary(L)), free_text(T, ?TITLE_MAX)} || {L, T} <- Kept]);
titles(_NotAMap) ->
    #{}.

field(Key, Notice) -> binary(maps:get(Key, Notice, <<>>)).

text(Bin) -> {text, Bin}.

%% Line breaks stay; every other control character goes, C0, DEL and C1 (U+009B
%% is a one-character CSI), so a terminal escape in a buyer's text never
%% reaches a reader's screen. So do the bidirectional marks, overrides and
%% isolates, which make text read differently from what it says. Then bounded,
%% by graphemes, so multibyte text is never cut mid-character.
free_text(Bin, Max) ->
    Clean = re:replace(binary(Bin),
                       <<"[\\x{00}-\\x{08}\\x{0B}\\x{0C}\\x{0E}-\\x{1F}\\x{7F}-\\x{9F}"
                         "\\x{061C}\\x{200E}\\x{200F}\\x{202A}-\\x{202E}\\x{2066}-\\x{2069}]">>,
                       <<>>, [global, unicode, {return, binary}]),
    text(clip(Clean, string:length(Clean), Max)).

clip(Bin, Len, Max) when Len =< Max -> Bin;
clip(Bin, _Len, Max) -> <<(string:slice(Bin, 0, Max))/binary, "…"/utf8>>.

binary(Bin) when is_binary(Bin) -> Bin;
binary(_NotText) -> <<>>.

integer(N) when is_integer(N), N >= 0 -> N;
integer(_NotACount) -> 0.

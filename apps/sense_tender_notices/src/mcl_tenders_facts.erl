%%% @doc The public contract of mcl-tenders: one fact, and nothing else leaves
%%% the sensor.
%%%
%%%   tender_notice_reported_v1   TED published a notice this sensor had not
%%%                               reported before
%%%
%%% The topic is a canonical macula app fact owned by org `mcl-tenders', app
%%% `tenders', domain `wire': `io.macula/mcl-tenders/tenders/wire/
%%% tender_notice_reported_v1'. The org segment is the schema owner and is fixed
%%% here, not deploy config. This module is the one schema the sensor and the
%%% company node both build against, so a change to it is one change to both.
%%%
%%% ONE TOPIC FOR EVERY NOTICE (T3 of the design's threat model). Country, CPV
%%% code and notice type are payload fields a company node filters on. A topic
%%% per code would tell every station on the path which codes a company
%%% subscribed to, which is the profile it must keep to itself.
%%%
%%% EVERYTHING MATCHING NEEDS, SO NOBODY ASKS (T3). A company node never sends
%%% the sensor a follow-up call ("give me notice X"), because that would tell
%%% the sensor which notices matched. The sensor serves no procedure at all.
%%%
%%% A CLOSED FIELD LIST (A5, T4). fact/1 reads only fields/0 from the notice:
%%% no contact data, and no url. The company node rebuilds the TED link from the
%%% publication number, so a link in a payload can never be followed.
%%%
%%% WHO REPORTED IT IS NOT IN THE PAYLOAD. macula delivers every event with the
%%% publisher its link verified, and a company node subscribes with the sensors
%%% it trusts as its sources (T4).
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

%% @doc Publish one notice and answer how it went. Synchronous, so the sweep
%% marks a notice reported only once it was: a dark mesh or a refused publish
%% answers an error, and the next sweep tries the notice again.
-spec report(parse_ted_notice:notice()) -> ok | {error, term()}.
report(Notice) ->
    mcl_om_pubsub:publish(topic(realm_name()), fact(Notice), #{mode => sync}).

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

%% Line breaks stay; every other control character goes, so a terminal escape
%% in a buyer's text never reaches a reader's screen. Then bounded, by
%% graphemes, so multibyte text is never cut mid-character.
free_text(Bin, Max) ->
    Clean = re:replace(binary(Bin), <<"[\\x{00}-\\x{08}\\x{0B}\\x{0C}\\x{0E}-\\x{1F}\\x{7F}]">>,
                       <<>>, [global, unicode, {return, binary}]),
    text(clip(Clean, string:length(Clean), Max)).

clip(Bin, Len, Max) when Len =< Max -> Bin;
clip(Bin, _Len, Max) -> <<(string:slice(Bin, 0, Max))/binary, "…"/utf8>>.

binary(Bin) when is_binary(Bin) -> Bin;
binary(_NotText) -> <<>>.

integer(N) when is_integer(N), N >= 0 -> N;
integer(_NotACount) -> 0.

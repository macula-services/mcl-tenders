%%% @doc Event `tender_spotted_v1': a notice fit the realm's profile, and its
%%% tender has a dossier. Carries the notice as tender_notice read it, and why
%%% it fit: the profile CPV codes that covered it and the keywords it hit.
-module(tender_spotted_v1).
-behaviour(evoq_event).

-export([event_type/0]).
-export([new/1, to_map/1]).

-record(tender_spotted_v1, {
    realm :: binary(),
    tender_id :: binary(),
    notice :: tender_notice:notice(),
    matched_cpv_codes :: [binary()],
    matched_keywords :: [binary()],
    spotted_at :: integer()
}).

-opaque t() :: #tender_spotted_v1{}.
-export_type([t/0]).

-spec event_type() -> binary().
event_type() -> <<"tender_spotted_v1">>.

-spec new(map()) -> t().
new(#{realm := Realm, tender_id := Id, notice := Notice, matched_cpv_codes := Cpv,
      matched_keywords := Keywords} = Params) ->
    #tender_spotted_v1{realm = Realm, tender_id = Id, notice = Notice, matched_cpv_codes = Cpv,
                       matched_keywords = Keywords,
                       spotted_at = maps:get(spotted_at, Params, erlang:system_time(millisecond))}.

%% The notice's fields sit flat in the event, beside the dossier's own.
-spec to_map(t()) -> map().
to_map(#tender_spotted_v1{realm = Realm, tender_id = Id, notice = Notice, matched_cpv_codes = Cpv,
                          matched_keywords = Keywords, spotted_at = At}) ->
    maps:merge(maps:with(tender_notice:fields(), Notice),
               #{event_type => <<"tender_spotted_v1">>, realm => Realm, tender_id => Id,
                 matched_cpv_codes => Cpv, matched_keywords => Keywords, spotted_at => At}).

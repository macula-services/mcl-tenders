%%% @doc Command `spot_tender_v1': a notice fits the realm's profile, so its
%%% tender gets a dossier.
%%%
%%% Issued by the process manager on_tender_notice_reported_v1_maybe_spot_tender
%%% for a contract notice or a prior information notice that tender_fit
%%% passed, with the profile codes and keywords that matched. The notice is
%%% tender_notice's, already checked field by field.
%%% @end
-module(spot_tender_v1).
-behaviour(evoq_command).

-export([command_type/0]).
-export([new/1, from_map/1, validate/1, to_map/1]).
-export([stream_id/1, get_realm/1, get_tender_id/1]).

-record(spot_tender_v1, {
    realm :: <<_:256>>,
    tender_id :: binary(),
    notice :: tender_notice:notice(),
    matched_cpv_codes :: [binary()],
    matched_keywords :: [binary()]
}).

-opaque t() :: #spot_tender_v1{}.
-export_type([t/0]).

-spec command_type() -> atom().
command_type() -> spot_tender_v1.

-spec new(map()) -> {ok, t()} | {error, atom()}.
new(#{realm := <<_:256>> = Realm, notice := #{} = Notice,
      reasons := #{matched_cpv_codes := Cpv, matched_keywords := Keywords}}) ->
    {ok, #spot_tender_v1{realm = Realm, tender_id = tender_notice:tender_id(Notice), notice = Notice,
                         matched_cpv_codes = Cpv, matched_keywords = Keywords}};
new(_) ->
    {error, invalid_spot_tender}.

-spec from_map(map()) -> {ok, t()} | {error, term()}.
from_map(#{realm := <<_:256>> = Realm, tender_id := Id, notice := #{} = Notice,
           matched_cpv_codes := Cpv, matched_keywords := Keywords})
  when is_binary(Id), is_list(Cpv), is_list(Keywords) ->
    {ok, #spot_tender_v1{realm = Realm, tender_id = Id, notice = Notice,
                         matched_cpv_codes = Cpv, matched_keywords = Keywords}};
from_map(_) ->
    {error, invalid_spot_tender}.

-spec validate(t()) -> ok | {error, term()}.
validate(#spot_tender_v1{}) -> ok.

-spec to_map(t()) -> map().
to_map(#spot_tender_v1{realm = Realm, tender_id = Id, notice = Notice,
                       matched_cpv_codes = Cpv, matched_keywords = Keywords}) ->
    #{command_type => spot_tender_v1, realm => Realm, tender_id => Id, notice => Notice,
      matched_cpv_codes => Cpv, matched_keywords => Keywords}.

-spec stream_id(t()) -> binary().
stream_id(#spot_tender_v1{realm = Realm, tender_id = Id}) ->
    tender_aggregate:stream_id(Realm, Id).

-spec get_realm(t()) -> <<_:256>>.
get_realm(#spot_tender_v1{realm = V}) -> V.

-spec get_tender_id(t()) -> binary().
get_tender_id(#spot_tender_v1{tender_id = V}) -> V.

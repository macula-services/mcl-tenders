%%% @doc Command `amend_tender_v1': TED published a correction to a tender the
%%% realm spotted.
%%%
%%% Issued by the process manager for a `correction' notice. A correction of a
%%% procedure that was never spotted leaves no event (tender_aggregate). The
%%% correction's deadline, value, titles and description replace the
%%% dossier's; a field the correction leaves empty keeps what was there.
%%% @end
-module(amend_tender_v1).
-behaviour(evoq_command).

-export([command_type/0]).
-export([new/1, from_map/1, validate/1, to_map/1]).
-export([stream_id/1, fields/0]).

-record(amend_tender_v1, {
    realm :: <<_:256>>,
    tender_id :: binary(),
    correction :: map()
}).

-opaque t() :: #amend_tender_v1{}.
-export_type([t/0]).

-spec command_type() -> atom().
command_type() -> amend_tender_v1.

%% @doc The notice fields a correction carries into the dossier.
-spec fields() -> [atom()].
fields() ->
    [publication_number, deadline_at, estimated_value, currency, titles, description,
     description_lang, published_at].

-spec new(map()) -> {ok, t()} | {error, atom()}.
new(#{realm := <<_:256>> = Realm, notice := #{} = Notice}) ->
    {ok, #amend_tender_v1{realm = Realm, tender_id = tender_notice:tender_id(Notice),
                          correction = maps:with(fields(), Notice)}};
new(_) ->
    {error, invalid_amend_tender}.

-spec from_map(map()) -> {ok, t()} | {error, term()}.
from_map(#{realm := <<_:256>> = Realm, tender_id := Id, correction := #{} = Correction})
  when is_binary(Id) ->
    {ok, #amend_tender_v1{realm = Realm, tender_id = Id, correction = Correction}};
from_map(_) ->
    {error, invalid_amend_tender}.

-spec validate(t()) -> ok | {error, term()}.
validate(#amend_tender_v1{}) -> ok.

-spec to_map(t()) -> map().
to_map(#amend_tender_v1{realm = Realm, tender_id = Id, correction = Correction}) ->
    #{command_type => amend_tender_v1, realm => Realm, tender_id => Id, correction => Correction}.

-spec stream_id(t()) -> binary().
stream_id(#amend_tender_v1{realm = Realm, tender_id = Id}) ->
    tender_aggregate:stream_id(Realm, Id).

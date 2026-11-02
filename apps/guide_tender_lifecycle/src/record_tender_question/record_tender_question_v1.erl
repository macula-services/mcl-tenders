%%% @doc Command `record_tender_question_v1': a question the buyer answers on a
%%% pursued tender is kept with it.
%%%
%%% Sent through the sealed `mcl-tenders/record_tender_question' procedure by a
%%% caller the realm granted the tenders role. The question is kept in NFC, up
%%% to 4000 bytes, line breaks allowed and no other control or invisible format
%%% character (tender_profile_text). Its `question_id' is the SHA-256 of that
%%% text, so the same question recorded twice is one question (the read model
%%% keeps who recorded it first). `recorded_by'
%%% is the node id macula verified for that call, never a field of the payload
%%% (T13). Only on a pursued tender (tender_aggregate).
%%% @end
-module(record_tender_question_v1).
-behaviour(evoq_command).

-export([command_type/0]).
-export([new/1, from_map/1, validate/1, to_map/1]).
-export([stream_id/1]).

-define(MAX_QUESTION_BYTES, 4000).

-record(record_tender_question_v1, {
    realm :: <<_:256>>,
    tender_id :: binary(),
    question_id :: binary(),
    question :: binary(),
    recorded_by :: <<_:256>>
}).

-opaque t() :: #record_tender_question_v1{}.
-export_type([t/0]).

-spec command_type() -> atom().
command_type() -> record_tender_question_v1.

%% @doc A command that exists is a valid one.
-spec new(map()) -> {ok, t()} | {error, atom()}.
new(#{realm := <<_:256>> = Realm} = Params) ->
    checked(maps:get(recorded_by, Params, undefined), maps:get(tender_id, Params, undefined),
            maps:get(question, Params, undefined), Realm);
new(_) ->
    {error, invalid_realm}.

-spec from_map(map()) -> {ok, t()} | {error, term()}.
from_map(#{realm := <<_:256>> = Realm, tender_id := Id, question_id := QId, question := Q,
           recorded_by := <<_:256>> = By})
  when is_binary(Id), is_binary(QId), is_binary(Q) ->
    {ok, #record_tender_question_v1{realm = Realm, tender_id = Id, question_id = QId,
                                    question = Q, recorded_by = By}};
from_map(_) ->
    {error, invalid_record_tender_question}.

-spec validate(t()) -> ok | {error, term()}.
validate(#record_tender_question_v1{}) -> ok.

-spec to_map(t()) -> map().
to_map(#record_tender_question_v1{realm = Realm, tender_id = Id, question_id = QId,
                                  question = Q, recorded_by = By}) ->
    #{command_type => record_tender_question_v1, realm => Realm, tender_id => Id,
      question_id => QId, question => Q, recorded_by => By}.

-spec stream_id(t()) -> binary().
stream_id(#record_tender_question_v1{realm = Realm, tender_id = Id}) ->
    tender_aggregate:stream_id(Realm, Id).

checked(<<_:256>> = By, Id, Question, Realm) ->
    identified(tender_notice:valid_tender_id(Id), Id, By, Question, Realm);
checked(_NoCaller, _Id, _Question, _Realm) ->
    {error, no_caller}.

identified(true, Id, By, Question, Realm) ->
    asked(tender_profile_text:checked(Question, 1, ?MAX_QUESTION_BYTES, lines), Id, By, Realm);
identified(false, _Id, _By, _Question, _Realm) ->
    {error, invalid_tender_id}.

asked({ok, Q}, Id, By, Realm) ->
    {ok, #record_tender_question_v1{realm = Realm, tender_id = Id,
                                    question_id = binary:encode_hex(crypto:hash(sha256, Q), lowercase),
                                    question = Q, recorded_by = By}};
asked(error, _Id, _By, _Realm) ->
    {error, invalid_question}.

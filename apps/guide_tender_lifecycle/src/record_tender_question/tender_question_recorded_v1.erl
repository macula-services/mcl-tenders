%%% @doc Event `tender_question_recorded_v1': a question on a pursued tender is
%%% kept with it. `question_id' is the SHA-256 of the question's NFC text, in
%%% lowercase hex; `recorded_by' is the caller macula verified (T13).
-module(tender_question_recorded_v1).
-behaviour(evoq_event).

-export([event_type/0]).
-export([new/1, to_map/1]).

-record(tender_question_recorded_v1, {
    realm :: binary(),
    tender_id :: binary(),
    question_id :: binary(),
    question :: binary(),
    recorded_by :: binary(),
    recorded_at :: integer()
}).

-opaque t() :: #tender_question_recorded_v1{}.
-export_type([t/0]).

-spec event_type() -> binary().
event_type() -> <<"tender_question_recorded_v1">>.

-spec new(map()) -> t().
new(#{realm := Realm, tender_id := Id, question_id := QId, question := Q,
      recorded_by := By} = Params) ->
    #tender_question_recorded_v1{realm = Realm, tender_id = Id, question_id = QId, question = Q,
                                 recorded_by = By,
                                 recorded_at = maps:get(recorded_at, Params,
                                                        erlang:system_time(millisecond))}.

-spec to_map(t()) -> map().
to_map(#tender_question_recorded_v1{realm = Realm, tender_id = Id, question_id = QId,
                                    question = Q, recorded_by = By, recorded_at = At}) ->
    #{event_type => <<"tender_question_recorded_v1">>, realm => Realm, tender_id => Id,
      question_id => QId, question => Q, recorded_by => By, recorded_at => At}.

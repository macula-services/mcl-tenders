%%% @doc Command `record_tender_outcome_v1': the realm learned whether its bid
%%% won or lost.
%%%
%%% Sent through the sealed `mcl-tenders/record_tender_outcome' procedure by a
%%% caller the realm granted the tenders role. `outcome' is `<<"won">>' or
%%% `<<"lost">>'. `recorded_by' is the node id macula verified for that call,
%%% never a field of the payload (T13). Once per tender, only after the bid
%%% went in (tender_aggregate).
%%% @end
-module(record_tender_outcome_v1).
-behaviour(evoq_command).

-export([command_type/0]).
-export([new/1, from_map/1, validate/1, to_map/1]).
-export([stream_id/1]).

-type outcome() :: binary().

-record(record_tender_outcome_v1, {
    realm :: <<_:256>>,
    tender_id :: binary(),
    outcome :: outcome(),
    recorded_by :: <<_:256>>
}).

-opaque t() :: #record_tender_outcome_v1{}.
-export_type([t/0]).

-spec command_type() -> atom().
command_type() -> record_tender_outcome_v1.

%% @doc A command that exists is a valid one.
-spec new(map()) -> {ok, t()} | {error, atom()}.
new(#{realm := <<_:256>> = Realm} = Params) ->
    checked(maps:get(recorded_by, Params, undefined), maps:get(tender_id, Params, undefined),
            maps:get(outcome, Params, undefined), Realm);
new(_) ->
    {error, invalid_realm}.

-spec from_map(map()) -> {ok, t()} | {error, term()}.
from_map(#{realm := <<_:256>> = Realm, tender_id := Id, outcome := Outcome,
           recorded_by := <<_:256>> = By})
  when is_binary(Id), (Outcome =:= <<"won">> orelse Outcome =:= <<"lost">>) ->
    {ok, #record_tender_outcome_v1{realm = Realm, tender_id = Id, outcome = Outcome, recorded_by = By}};
from_map(_) ->
    {error, invalid_record_tender_outcome}.

-spec validate(t()) -> ok | {error, term()}.
validate(#record_tender_outcome_v1{}) -> ok.

-spec to_map(t()) -> map().
to_map(#record_tender_outcome_v1{realm = Realm, tender_id = Id, outcome = Outcome, recorded_by = By}) ->
    #{command_type => record_tender_outcome_v1, realm => Realm, tender_id => Id,
      outcome => Outcome, recorded_by => By}.

-spec stream_id(t()) -> binary().
stream_id(#record_tender_outcome_v1{realm = Realm, tender_id = Id}) ->
    tender_aggregate:stream_id(Realm, Id).

checked(<<_:256>> = By, Id, Outcome, Realm) ->
    identified(tender_notice:valid_tender_id(Id), Id, By, Outcome, Realm);
checked(_NoCaller, _Id, _Outcome, _Realm) ->
    {error, no_caller}.

identified(true, Id, By, Outcome, Realm) -> decided(Outcome, Id, By, Realm);
identified(false, _Id, _By, _Outcome, _Realm) -> {error, invalid_tender_id}.

decided(Outcome, Id, By, Realm) when Outcome =:= <<"won">>; Outcome =:= <<"lost">> ->
    {ok, #record_tender_outcome_v1{realm = Realm, tender_id = Id, outcome = Outcome, recorded_by = By}};
decided(_Outcome, _Id, _By, _Realm) ->
    {error, invalid_outcome}.

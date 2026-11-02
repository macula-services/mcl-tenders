%%% @doc Command `dismiss_tender_v1': the bid team says a spotted tender is
%%% not for the realm.
%%%
%%% Sent through the sealed `mcl-tenders/dismiss_tender' procedure by a caller
%%% the realm granted the tenders role. `dismissed_by' is the node id macula
%%% verified for that call, never a field of the payload (T13). Once per
%%% tender (tender_aggregate).
%%% @end
-module(dismiss_tender_v1).
-behaviour(evoq_command).

-export([command_type/0]).
-export([new/1, from_map/1, validate/1, to_map/1]).
-export([stream_id/1]).

-record(dismiss_tender_v1, {
    realm :: <<_:256>>,
    tender_id :: binary(),
    dismissed_by :: <<_:256>>
}).

-opaque t() :: #dismiss_tender_v1{}.
-export_type([t/0]).

-spec command_type() -> atom().
command_type() -> dismiss_tender_v1.

%% @doc A command that exists is a valid one.
-spec new(map()) -> {ok, t()} | {error, atom()}.
new(#{realm := <<_:256>> = Realm} = Params) ->
    checked(maps:get(dismissed_by, Params, undefined), maps:get(tender_id, Params, undefined), Realm);
new(_) ->
    {error, invalid_realm}.

-spec from_map(map()) -> {ok, t()} | {error, term()}.
from_map(#{realm := <<_:256>> = Realm, tender_id := Id, dismissed_by := <<_:256>> = By})
  when is_binary(Id) ->
    {ok, #dismiss_tender_v1{realm = Realm, tender_id = Id, dismissed_by = By}};
from_map(_) ->
    {error, invalid_dismiss_tender}.

-spec validate(t()) -> ok | {error, term()}.
validate(#dismiss_tender_v1{}) -> ok.

-spec to_map(t()) -> map().
to_map(#dismiss_tender_v1{realm = Realm, tender_id = Id, dismissed_by = By}) ->
    #{command_type => dismiss_tender_v1, realm => Realm, tender_id => Id, dismissed_by => By}.

-spec stream_id(t()) -> binary().
stream_id(#dismiss_tender_v1{realm = Realm, tender_id = Id}) ->
    tender_aggregate:stream_id(Realm, Id).

checked(<<_:256>> = By, Id, Realm) -> identified(tender_notice:valid_tender_id(Id), Id, By, Realm);
checked(_NoCaller, _Id, _Realm) -> {error, no_caller}.

identified(true, Id, By, Realm) -> {ok, #dismiss_tender_v1{realm = Realm, tender_id = Id, dismissed_by = By}};
identified(false, _Id, _By, _Realm) -> {error, invalid_tender_id}.

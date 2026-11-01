%%% @doc Command `initiate_tender_profile_v1'.
%%%
%%% The birth of the realm's tenders profile, when mcl-tenders first boots in
%%% the realm. One per realm: the realm id keys the stream.
%%% @end
-module(initiate_tender_profile_v1).
-behaviour(evoq_command).

-export([command_type/0]).
-export([new/1, from_map/1, validate/1, to_map/1]).
-export([stream_id/1, get_realm/1]).

-record(initiate_tender_profile_v1, {
    realm :: <<_:256>>
}).

-opaque t() :: #initiate_tender_profile_v1{}.
-export_type([t/0]).

-spec command_type() -> atom().
command_type() -> initiate_tender_profile_v1.

-spec new(map()) -> {ok, t()} | {error, term()}.
new(Params) -> from_map(Params).

-spec from_map(map()) -> {ok, t()} | {error, term()}.
from_map(#{realm := <<_:256>> = Realm}) ->
    {ok, #initiate_tender_profile_v1{realm = Realm}};
from_map(_) ->
    {error, invalid_realm}.

-spec validate(t()) -> ok | {error, term()}.
validate(#initiate_tender_profile_v1{}) -> ok.

-spec to_map(t()) -> map().
to_map(#initiate_tender_profile_v1{realm = Realm}) ->
    #{command_type => initiate_tender_profile_v1, realm => Realm}.

-spec stream_id(t()) -> binary().
stream_id(#initiate_tender_profile_v1{realm = Realm}) ->
    tender_profile_aggregate:stream_id(Realm).

-spec get_realm(t()) -> <<_:256>>.
get_realm(#initiate_tender_profile_v1{realm = V}) -> V.

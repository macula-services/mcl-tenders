%%% @doc Command `archive_tender_profile_v1'.
%%%
%%% The end of the realm's tenders profile: the realm no longer looks for
%%% public tenders. `archived_by' is the caller's node id, kept so the realm
%%% can see who stopped its search. Archived is terminal (tender_profile_aggregate).
%%% @end
-module(archive_tender_profile_v1).
-behaviour(evoq_command).

-export([command_type/0]).
-export([new/1, from_map/1, validate/1, to_map/1]).
-export([stream_id/1, get_realm/1, get_archived_by/1]).

-record(archive_tender_profile_v1, {
    realm :: <<_:256>>,
    archived_by :: <<_:256>>
}).

-opaque t() :: #archive_tender_profile_v1{}.
-export_type([t/0]).

-spec command_type() -> atom().
command_type() -> archive_tender_profile_v1.

-spec new(map()) -> {ok, t()} | {error, atom()}.
new(#{realm := <<_:256>> = Realm} = Params) ->
    by_member(maps:get(archived_by, Params, undefined), Realm);
new(_) ->
    {error, invalid_realm}.

by_member(<<_:256>> = By, Realm) -> {ok, #archive_tender_profile_v1{realm = Realm, archived_by = By}};
by_member(_Missing, _Realm) -> {error, no_caller}.

%% @doc Rebuilds a command already validated by new/1, as evoq hands it back.
-spec from_map(map()) -> {ok, t()} | {error, term()}.
from_map(#{realm := <<_:256>> = Realm, archived_by := <<_:256>> = By}) ->
    {ok, #archive_tender_profile_v1{realm = Realm, archived_by = By}};
from_map(_) ->
    {error, invalid_tender_profile_archive}.

-spec validate(t()) -> ok | {error, term()}.
validate(#archive_tender_profile_v1{}) -> ok.

-spec to_map(t()) -> map().
to_map(#archive_tender_profile_v1{realm = Realm, archived_by = By}) ->
    #{command_type => archive_tender_profile_v1, realm => Realm, archived_by => By}.

-spec stream_id(t()) -> binary().
stream_id(#archive_tender_profile_v1{realm = Realm}) ->
    tender_profile_aggregate:stream_id(Realm).

-spec get_realm(t()) -> <<_:256>>.
get_realm(#archive_tender_profile_v1{realm = V}) -> V.

-spec get_archived_by(t()) -> <<_:256>>.
get_archived_by(#archive_tender_profile_v1{archived_by = V}) -> V.

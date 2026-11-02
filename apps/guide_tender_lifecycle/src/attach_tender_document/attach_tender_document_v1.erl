%%% @doc Command `attach_tender_document_v1': a document of the bid team's
%%% pursuit is kept with the tender.
%%%
%%% Sent through the sealed `mcl-tenders/attach_tender_document' procedure by a
%%% caller the realm granted the tenders role. It names the document, its
%%% SHA-256 and where the file lies on the node; the file itself never travels
%%% and never leaves the node. `attached_by' is the node id macula verified for
%%% that call, never a field of the payload (T13). Only on a pursued tender
%%% (tender_aggregate); attaching the same digest again renames or moves it.
%%% @end
-module(attach_tender_document_v1).
-behaviour(evoq_command).

-export([command_type/0]).
-export([new/1, from_map/1, validate/1, to_map/1]).
-export([stream_id/1]).

-define(SHA256, "^[0-9a-f]{64}\\z").
-define(MAX_NAME_BYTES, 255).
-define(MAX_LOCATION_BYTES, 1024).

-record(attach_tender_document_v1, {
    realm :: <<_:256>>,
    tender_id :: binary(),
    name :: binary(),
    sha256 :: binary(),
    location :: binary(),
    attached_by :: <<_:256>>
}).

-opaque t() :: #attach_tender_document_v1{}.
-export_type([t/0]).

-spec command_type() -> atom().
command_type() -> attach_tender_document_v1.

%% @doc A command that exists is a valid one: the name and the location are
%% kept in NFC, one line each, with no control or invisible format character
%% (tender_profile_text), and the digest is 64 lowercase hex digits.
-spec new(map()) -> {ok, t()} | {error, atom()}.
new(#{realm := <<_:256>> = Realm} = Params) ->
    checked(Realm, [{attached_by, caller(maps:get(attached_by, Params, undefined))},
                    {tender_id, tender_id(maps:get(tender_id, Params, undefined))},
                    {name, text(maps:get(name, Params, undefined), ?MAX_NAME_BYTES,
                                invalid_document_name)},
                    {sha256, digest(maps:get(sha256, Params, undefined))},
                    {location, text(maps:get(location, Params, undefined), ?MAX_LOCATION_BYTES,
                                    invalid_location)}], #{});
new(_) ->
    {error, invalid_realm}.

-spec from_map(map()) -> {ok, t()} | {error, term()}.
from_map(#{realm := <<_:256>> = Realm, tender_id := Id, name := Name, sha256 := Sha,
           location := Location, attached_by := <<_:256>> = By})
  when is_binary(Id), is_binary(Name), is_binary(Sha), is_binary(Location) ->
    {ok, #attach_tender_document_v1{realm = Realm, tender_id = Id, name = Name, sha256 = Sha,
                                    location = Location, attached_by = By}};
from_map(_) ->
    {error, invalid_attach_tender_document}.

-spec validate(t()) -> ok | {error, term()}.
validate(#attach_tender_document_v1{}) -> ok.

-spec to_map(t()) -> map().
to_map(#attach_tender_document_v1{realm = Realm, tender_id = Id, name = Name, sha256 = Sha,
                                  location = Location, attached_by = By}) ->
    #{command_type => attach_tender_document_v1, realm => Realm, tender_id => Id, name => Name,
      sha256 => Sha, location => Location, attached_by => By}.

-spec stream_id(t()) -> binary().
stream_id(#attach_tender_document_v1{realm = Realm, tender_id = Id}) ->
    tender_aggregate:stream_id(Realm, Id).

%% Each field in order; the first one refused is the reason.
checked(_Realm, [{_Field, {error, _} = Refused} | _Rest], _Acc) ->
    Refused;
checked(Realm, [{Field, {ok, Value}} | Rest], Acc) ->
    checked(Realm, Rest, Acc#{Field => Value});
checked(Realm, [], #{attached_by := By, tender_id := Id, name := Name, sha256 := Sha,
                     location := Location}) ->
    {ok, #attach_tender_document_v1{realm = Realm, tender_id = Id, name = Name, sha256 = Sha,
                                    location = Location, attached_by = By}}.

caller(<<_:256>> = By) -> {ok, By};
caller(_NoCaller) -> {error, no_caller}.

tender_id(Id) -> identified(tender_notice:valid_tender_id(Id), Id).

identified(true, Id) -> {ok, Id};
identified(false, _Id) -> {error, invalid_tender_id}.

text(Text, Max, Reason) -> kept(tender_profile_text:checked(Text, 1, Max, line), Reason).

kept({ok, Nfc}, _Reason) -> {ok, Nfc};
kept(error, Reason) -> {error, Reason}.

digest(Sha) when is_binary(Sha) -> hexed(re:run(Sha, ?SHA256, [{capture, none}]), Sha);
digest(_Sha) -> {error, invalid_sha256}.

hexed(match, Sha) -> {ok, Sha};
hexed(nomatch, _Sha) -> {error, invalid_sha256}.

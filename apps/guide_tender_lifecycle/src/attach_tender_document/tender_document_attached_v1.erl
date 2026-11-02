%%% @doc Event `tender_document_attached_v1': a document of the pursuit is kept
%%% with the tender: its name, its SHA-256 (64 lowercase hex digits) and where
%%% the file lies on the node. `attached_by' is the caller macula verified
%%% (T13). The file itself is not in the event.
-module(tender_document_attached_v1).
-behaviour(evoq_event).

-export([event_type/0]).
-export([new/1, to_map/1]).

-record(tender_document_attached_v1, {
    realm :: binary(),
    tender_id :: binary(),
    name :: binary(),
    sha256 :: binary(),
    location :: binary(),
    attached_by :: binary(),
    attached_at :: integer()
}).

-opaque t() :: #tender_document_attached_v1{}.
-export_type([t/0]).

-spec event_type() -> binary().
event_type() -> <<"tender_document_attached_v1">>.

-spec new(map()) -> t().
new(#{realm := Realm, tender_id := Id, name := Name, sha256 := Sha, location := Location,
      attached_by := By} = Params) ->
    #tender_document_attached_v1{realm = Realm, tender_id = Id, name = Name, sha256 = Sha,
                                 location = Location, attached_by = By,
                                 attached_at = maps:get(attached_at, Params,
                                                        erlang:system_time(millisecond))}.

-spec to_map(t()) -> map().
to_map(#tender_document_attached_v1{realm = Realm, tender_id = Id, name = Name, sha256 = Sha,
                                    location = Location, attached_by = By, attached_at = At}) ->
    #{event_type => <<"tender_document_attached_v1">>, realm => Realm, tender_id => Id,
      name => Name, sha256 => Sha, location => Location, attached_by => By, attached_at => At}.

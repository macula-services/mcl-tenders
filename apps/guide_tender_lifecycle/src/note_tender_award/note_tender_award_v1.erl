%%% @doc Command `note_tender_award_v1': the buyer published the award of a
%%% tender the realm spotted.
%%%
%%% Issued by the process manager for an `award' notice. Once per tender: the
%%% first award notice is the one noted (tender_aggregate). Who won is on TED,
%%% behind the rebuilt link; the realm records its own outcome in #4b.
%%% @end
-module(note_tender_award_v1).
-behaviour(evoq_command).

-export([command_type/0]).
-export([new/1, from_map/1, validate/1, to_map/1]).
-export([stream_id/1]).

-record(note_tender_award_v1, {
    realm :: <<_:256>>,
    tender_id :: binary(),
    publication_number :: binary(),
    published_at :: non_neg_integer()
}).

-opaque t() :: #note_tender_award_v1{}.
-export_type([t/0]).

-spec command_type() -> atom().
command_type() -> note_tender_award_v1.

-spec new(map()) -> {ok, t()} | {error, atom()}.
new(#{realm := <<_:256>> = Realm,
      notice := #{publication_number := Number, published_at := At} = Notice}) ->
    {ok, #note_tender_award_v1{realm = Realm, tender_id = tender_notice:tender_id(Notice),
                               publication_number = Number, published_at = At}};
new(_) ->
    {error, invalid_note_tender_award}.

-spec from_map(map()) -> {ok, t()} | {error, term()}.
from_map(#{realm := <<_:256>> = Realm, tender_id := Id, publication_number := Number,
           published_at := At})
  when is_binary(Id), is_binary(Number), is_integer(At) ->
    {ok, #note_tender_award_v1{realm = Realm, tender_id = Id, publication_number = Number,
                               published_at = At}};
from_map(_) ->
    {error, invalid_note_tender_award}.

-spec validate(t()) -> ok | {error, term()}.
validate(#note_tender_award_v1{}) -> ok.

-spec to_map(t()) -> map().
to_map(#note_tender_award_v1{realm = Realm, tender_id = Id, publication_number = Number,
                             published_at = At}) ->
    #{command_type => note_tender_award_v1, realm => Realm, tender_id => Id,
      publication_number => Number, published_at => At}.

-spec stream_id(t()) -> binary().
stream_id(#note_tender_award_v1{realm = Realm, tender_id = Id}) ->
    tender_aggregate:stream_id(Realm, Id).

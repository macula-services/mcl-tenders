%%% @doc Aggregate for one tender: its dossier.
%%%
%%% One dossier per tender the realm's profile fits, keyed by TED's procedure
%%% id, so the procedure's corrections and its award fold into the one entry.
%%% A notice with no procedure id is keyed by its publication number instead.
%%% Lifecycle so far (#4a): spot_tender (once, when a notice fits) ->
%%% amend_tender (each correction) | note_tender_award (once) |
%%% dismiss_tender (once, "not for us"). The pursuit desks come in #4b.
%%%
%%% The lifecycle rules live here, in execute/2; the desk handlers only
%%% validate a payload and build the event. The state keeps the flags and
%%% never a notice's text.
%%% @end
-module(tender_aggregate).
-behaviour(evoq_aggregate).

-include("tender_status.hrl").

-export([init/1, execute/2, apply/2]).
-export([state_module/0, stream_id/2, store_id/0]).

-spec state_module() -> module().
state_module() -> tender_state.

%% @doc The store the tender streams live in: the one mcl_tenders opens.
-spec store_id() -> atom().
store_id() -> tender_profile_aggregate:store_id().

%% @doc reckon-db stream ids must match ^[a-z]{1,32}-[a-f0-9]{32}$, so a
%% tender's stream is addressed by a 128-bit digest of the realm and the
%% tender id. Events carry both themselves.
-spec stream_id(<<_:256>>, binary()) -> binary().
stream_id(Realm, TenderId) ->
    Digest = binary:part(crypto:hash(sha256, <<Realm/binary, TenderId/binary>>), 0, 16),
    <<"tender-", (binary:encode_hex(Digest, lowercase))/binary>>.

init(StreamId) ->
    {ok, tender_state:new(StreamId)}.

execute(State, #{command_type := CmdType} = Payload) ->
    do_execute(CmdType, tender_state:status(State), Payload);
execute(_State, _Unknown) ->
    {error, unknown_command}.

apply(State, Event) ->
    tender_state:apply_event(State, Event).

do_execute(spot_tender_v1, Status, Payload) ->
    spot(evoq_bit_flags:has(Status, ?TENDER_SPOTTED), Payload);
do_execute(amend_tender_v1, Status, Payload) ->
    spotted(Status, fun() -> maybe_amend_tender:handle_from_map(Payload) end);
do_execute(note_tender_award_v1, Status, Payload) ->
    spotted(Status, fun() -> note_award(evoq_bit_flags:has(Status, ?TENDER_AWARD_PUBLISHED), Payload) end);
do_execute(dismiss_tender_v1, Status, Payload) ->
    spotted(Status, fun() -> dismiss(evoq_bit_flags:has(Status, ?TENDER_DISMISSED), Payload) end);
do_execute(_Unknown, _Status, _Payload) ->
    {error, unknown_command}.

spot(true, _Payload) -> {error, already_spotted};
spot(false, Payload) -> maybe_spot_tender:handle_from_map(Payload).

%% Every desk but spot_tender acts on a tender that was spotted: a correction
%% or an award of a procedure the realm never followed leaves no event.
spotted(Status, Next) ->
    run(evoq_bit_flags:has(Status, ?TENDER_SPOTTED), Next).

run(true, Next) -> Next();
run(false, _Next) -> {error, not_spotted}.

note_award(true, _Payload) -> {error, already_noted};
note_award(false, Payload) -> maybe_note_tender_award:handle_from_map(Payload).

dismiss(true, _Payload) -> {error, already_dismissed};
dismiss(false, Payload) -> maybe_dismiss_tender:handle_from_map(Payload).

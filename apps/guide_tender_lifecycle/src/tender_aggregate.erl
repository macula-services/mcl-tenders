%%% @doc Aggregate for one tender: its dossier.
%%%
%%% One dossier per tender the realm's profile fits, keyed by TED's procedure
%%% id, so the procedure's corrections and its award fold into the one entry.
%%% A notice with no procedure id is keyed by its publication number instead.
%%% Lifecycle: spot_tender (once, when a notice fits) -> amend_tender (each
%%% correction) | note_tender_award (once) | dismiss_tender (once, "not for
%%% us", before any pursuit). The pursuit (#4b): pursue_tender (bid, once) ->
%%% decline_tender (no bid after all) | submit_tender_bid -> record_tender_outcome
%%% (won or lost, once). Corrections and the award keep folding into the same
%%% dossier while it is pursued, so a pursuit sees them without anyone retyping
%%% them.
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
    ruled(Status, [{lacks, ?TENDER_SPOTTED, not_spotted}],
          fun() -> maybe_amend_tender:handle_from_map(Payload) end);
do_execute(note_tender_award_v1, Status, Payload) ->
    ruled(Status, [{lacks, ?TENDER_SPOTTED, not_spotted},
                   {has, ?TENDER_AWARD_PUBLISHED, already_noted}],
          fun() -> maybe_note_tender_award:handle_from_map(Payload) end);
do_execute(dismiss_tender_v1, Status, Payload) ->
    ruled(Status, [{lacks, ?TENDER_SPOTTED, not_spotted},
                   {has, ?TENDER_DISMISSED, already_dismissed},
                   {has, ?TENDER_PURSUED, pursued}],
          fun() -> maybe_dismiss_tender:handle_from_map(Payload) end);
do_execute(pursue_tender_v1, Status, Payload) ->
    ruled(Status, [{lacks, ?TENDER_SPOTTED, not_spotted},
                   {has, ?TENDER_DISMISSED, dismissed},
                   {has, ?TENDER_PURSUED, already_pursued}],
          fun() -> maybe_pursue_tender:handle_from_map(Payload) end);
do_execute(decline_tender_v1, Status, Payload) ->
    ruled(Status, [{lacks, ?TENDER_SPOTTED, not_spotted},
                   {lacks, ?TENDER_PURSUED, not_pursued},
                   {has, ?TENDER_DECLINED, already_declined},
                   {has, ?TENDER_BID_SUBMITTED, already_submitted}],
          fun() -> maybe_decline_tender:handle_from_map(Payload) end);
do_execute(submit_tender_bid_v1, Status, Payload) ->
    ruled(Status, [{lacks, ?TENDER_SPOTTED, not_spotted},
                   {lacks, ?TENDER_PURSUED, not_pursued},
                   {has, ?TENDER_DECLINED, declined},
                   {has, ?TENDER_BID_SUBMITTED, already_submitted}],
          fun() -> maybe_submit_tender_bid:handle_from_map(Payload) end);
do_execute(record_tender_outcome_v1, Status, Payload) ->
    ruled(Status, [{lacks, ?TENDER_SPOTTED, not_spotted},
                   {lacks, ?TENDER_BID_SUBMITTED, not_submitted},
                   {has, [?TENDER_WON, ?TENDER_LOST], already_recorded}],
          fun() -> maybe_record_tender_outcome:handle_from_map(Payload) end);
do_execute(_Unknown, _Status, _Payload) ->
    {error, unknown_command}.

spot(true, _Payload) -> {error, already_spotted};
spot(false, Payload) -> maybe_spot_tender:handle_from_map(Payload).

%% The rules of a desk, in order: the first one the status breaks is the
%% refusal; none broken, the desk's handler builds the event. `{has, F, R}' is
%% broken when F (a flag, or any of a list of flags) is set, `{lacks, F, R}'
%% when it is not.
ruled(_Status, [], Next) ->
    Next();
ruled(Status, [{Test, Flags, Reason} | Rest], Next) ->
    broken(Test, evoq_bit_flags:has_any(Status, flags(Flags)), Reason,
           fun() -> ruled(Status, Rest, Next) end).

broken(has, true, Reason, _Continue) -> {error, Reason};
broken(lacks, false, Reason, _Continue) -> {error, Reason};
broken(_Test, _Set, _Reason, Continue) -> Continue().

flags(Flags) when is_list(Flags) -> Flags;
flags(Flag) -> [Flag].

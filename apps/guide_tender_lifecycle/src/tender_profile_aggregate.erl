%%% @doc Aggregate for the realm's tenders profile.
%%%
%%% One profile per realm, keyed by the realm id: what the realm looks for in a
%%% public tender. Lifecycle: initiate_tender_profile (once, when mcl-tenders
%%% first boots in the realm) -> describe_tender_profile (any number of times,
%%% each replacing the last).
%%%
%%% The lifecycle rules live here, in execute/2; the desk handlers only
%%% validate a payload and build the event. The state keeps the flags and the
%%% realm and never a profile term, so the aggregate process cannot put one in
%%% a crash report (T8).
%%% @end
-module(tender_profile_aggregate).
-behaviour(evoq_aggregate).

-include("tender_profile_status.hrl").

-export([init/1, execute/2, apply/2]).
-export([state_module/0, stream_id/1, store_id/0]).

-spec state_module() -> module().
state_module() -> tender_profile_state.

%% @doc The store the profile stream lives in: the one mcl_tenders opens.
%% mcl_tenders' tests assert it agrees with mcl_tenders_service:event_store/0.
-spec store_id() -> atom().
store_id() -> mcl_tenders_store.

%% @doc reckon-db stream ids must match ^[a-z]{1,32}-[a-f0-9]{32}$, so the
%% stream is addressed by a 128-bit digest of the realm id. Events carry the
%% realm id itself.
-spec stream_id(<<_:256>>) -> binary().
stream_id(Realm) ->
    Digest = binary:part(crypto:hash(sha256, Realm), 0, 16),
    <<"tenderprofile-", (binary:encode_hex(Digest, lowercase))/binary>>.

init(Realm) ->
    {ok, tender_profile_state:new(Realm)}.

execute(State, #{command_type := CmdType} = Payload) ->
    do_execute(CmdType, tender_profile_state:status(State), Payload);
execute(_State, _Unknown) ->
    {error, unknown_command}.

apply(State, Event) ->
    tender_profile_state:apply_event(State, Event).

do_execute(initiate_tender_profile_v1, Status, Payload) ->
    initiate(evoq_bit_flags:has(Status, ?TENDER_PROFILE_INITIATED), Payload);
do_execute(describe_tender_profile_v1, Status, Payload) ->
    describe(evoq_bit_flags:has(Status, ?TENDER_PROFILE_INITIATED), Payload);
do_execute(_Unknown, _Status, _Payload) ->
    {error, unknown_command}.

initiate(true, _Payload) -> {error, already_initiated};
initiate(false, Payload) -> maybe_initiate_tender_profile:handle_from_map(Payload).

describe(false, _Payload) -> {error, not_initiated};
describe(true, Payload) -> maybe_describe_tender_profile:handle_from_map(Payload).

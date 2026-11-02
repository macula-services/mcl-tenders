%%% @doc The released pipeline, stood up for a test with no mesh: a real
%%% reckon-db store, the store subscription, evoq's router, the projections,
%%% the SQLite read model, the query store, and mcl_om's identity holding the
%%% realm, so every desk and responder runs as it does on a node.
%%%
%%% Shared by mcl_tenders_read_side_tests, mcl_tenders_dossier_tests,
%%% mcl_tenders_wire_replies_tests and mcl_tenders_no_profile_in_logs_tests.
-module(mcl_tenders_pipeline).

-include_lib("reckon_db/include/reckon_db.hrl").
-include_lib("eunit/include/eunit.hrl").

-export([start/1, stop/1, realm/0, eventually/2, call/3, reported/1]).

%% Synthetic: this repository is public.
-define(REALM_NAME, <<"io.example">>).

%% @doc The realm the identity holds: sha256 of the synthetic realm name.
-spec realm() -> <<_:256>>.
realm() -> crypto:hash(sha256, ?REALM_NAME).

-spec start(string()) -> term().
start(Suite) ->
    Dir = filename:join(["/tmp", Suite, integer_to_list(erlang:unique_integer([positive]))]),
    _ = application:load(evoq),
    _ = application:load(mcl_om),
    [ok = application:set_env(evoq, K, V)
     || {K, V} <- [{event_store_adapter, reckon_evoq_adapter},
                   {subscription_adapter, reckon_evoq_adapter},
                   {snapshot_store_adapter, reckon_evoq_adapter},
                   {store_id, mcl_tenders_store}]],
    ok = application:set_env(mcl_om, realm, binary:encode_hex(realm(), lowercase)),
    os:putenv("MCL_DATA_DIR", Dir),
    {ok, Started} = application:ensure_all_started([reckon_db, evoq, reckon_evoq, esqlite,
                                                    project_tenders]),
    {ok, _} = reckon_db_sup:start_store(#store_config{store_id = mcl_tenders_store,
                                                      data_dir = filename:join(Dir, "store"),
                                                      mode = single}),
    Pids = [started(evoq_store_subscription:start_link(mcl_tenders_store)),
            started(tenders_query_store:start_link(project_tenders_sup:sqlite_path())),
            started(mcl_om_identity:start_link())],
    {Dir, Started, Pids}.

-spec stop(term()) -> ok.
stop({Dir, Started, Pids}) ->
    [exit(Pid, shutdown) || Pid <- lists:reverse(Pids)],
    [application:stop(App) || App <- lists:reverse(Started)],
    ok = application:unset_env(mcl_om, realm),
    os:unsetenv("MCL_DATA_DIR"),
    _ = file:del_dir_r(Dir),
    ok.

started({ok, Pid}) ->
    unlink(Pid),
    Pid.

%% @doc Projections are asynchronous: ask until the answer is the expected one.
-spec eventually(fun(() -> term()), term()) -> ok.
eventually(Fun, Expected) -> eventually(Fun, Expected, 100).

eventually(Fun, Expected, 0) -> ?assertEqual(Expected, Fun());
eventually(Fun, Expected, Tries) -> again(Fun(), Fun, Expected, Tries).

again(Expected, _Fun, Expected, _Tries) -> ok;
again(_Other, Fun, Expected, Tries) -> timer:sleep(100), eventually(Fun, Expected, Tries - 1).

%% @doc A procedure's responder called as macula calls it: the args encoded and
%% strictly decoded (every key and string arrives as `{text, _}'), the signer
%% merged in as `caller' unless it is `undefined', and the reply back through
%% the same codec, its keys as plain binaries.
-spec call(binary(), map(), binary() | undefined) -> {binary(), map()}.
call(Name, Args, Caller) ->
    Responder = binary_to_atom(<<Name/binary, "_responder">>),
    {ok, Payload} = macula_record_cbor:decode_strict(macula_record_cbor:encode(Args)),
    {ok, St} = Responder:init([]),
    {reply, Reply, _} = Responder:handle_request(with_caller(Payload, Caller), St),
    {ok, Decoded} = macula_record_cbor:decode_strict(macula_record_cbor:encode(Reply)),
    {Name, plain_keys(Decoded)}.

with_caller(Payload, undefined) -> Payload;
with_caller(Payload, Caller) -> Payload#{caller => Caller}.

plain_keys(Map) when is_map(Map) ->
    maps:from_list([{key(K), plain_keys(V)} || K := V <- Map]);
plain_keys(List) when is_list(List) -> [plain_keys(V) || V <- List];
plain_keys(Other) -> Other.

key({text, K}) -> K.

%% @doc One `tender_notice_reported_v1' fact through the process manager's
%% decision, as it arrives from the realm's sensor, with the realm, the profile
%% and the desks all live. The day's intake admits it: tender_intake's own
%% tests hold the cap.
-spec reported(map()) -> {atom(), term()}.
reported(Fact) ->
    on_tender_notice_reported_v1_maybe_spot_tender:handled(
      Fact, #{realm => fun mcl_om:realm/0,
              profile => fun get_tender_profile:find/1,
              admit => fun() -> ok end,
              spotted => fun() -> ok end,
              noted => fun() -> ok end,
              dispatch => fun dispatched/2}).

dispatched(spot_tender, Cmd) -> maybe_spot_tender:dispatch(Cmd);
dispatched(amend_tender, Cmd) -> maybe_amend_tender:dispatch(Cmd);
dispatched(note_tender_award, Cmd) -> maybe_note_tender_award:dispatch(Cmd).

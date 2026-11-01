%% @doc The PRJ department's SQLite store: one gen_server owning one esqlite
%% connection, the only writer of the read model.
%%
%% A NIF connection belongs to the process that opened it, so every write goes
%% through this process. The DDL lives here and only here; query_tenders reads
%% the schema this module creates, and a schema-contract test pins the columns
%% the query desks select to the columns this module declares.
%%
%% THE SCHEMA MOVES FORWARD IN PLACE. schema/0 is the table as 0.1.0 created
%% it and never changes; migrations/0 is every change since, each applied once,
%% in a transaction, on the boot that finds the file's PRAGMA user_version
%% below it. A box that ran an earlier release keeps its rows; a new file goes
%% through the same steps.
%%
%% Every write is one upsert that sets only the columns of the event it
%% projects, so events of one stream may arrive in any order. The description
%% carries its own version, and a write older than what is there changes
%% nothing. A row a description created before its initiation has
%% initiated_at NULL, and the query side treats it as not there.
%%
%% ⚠ A WRITE CARRIES THE PROFILE, AND NO LOG MAY (T8). The write's arguments
%% are the realm's CPV codes, countries, keywords, exclusions and description.
%% So three things keep them out of every report:
%%
%%   - a raise while serving a request is answered, not exited on: the exit
%%     reason of a NIF's badarg carries that call's arguments in its top frame,
%%     and the process's exit reason reaches the proc_lib crash report and the
%%     supervisor's, where format_status/1 cannot reach;
%%   - format_status/1 drops the request's arguments, and every frame's, from
%%     whatever crash report this process does make;
%%   - exec/2 answers a dead or stuck store as `{error, store_unavailable}'
%%     rather than letting gen_server:call exit the caller with the request,
%%     arguments and all, in its exit reason.
-module(tenders_read_model_store).

-behaviour(gen_server).

-export([start_link/1, exec/2, q/2, schema/0, migrations/0]).
-export([init/1, handle_call/3, handle_cast/2, handle_info/2, terminate/2, format_status/1]).

-record(state, {conn :: esqlite3:esqlite3()}).

%% @doc The schema, in creation order: the one place the read model's shape is
%% written down. The realm is lowercase hex; a list is newline-separated (no
%% code or term can carry a control character).
-spec schema() -> [string()].
schema() ->
    ["CREATE TABLE IF NOT EXISTS tender_profiles ("
     " realm              TEXT PRIMARY KEY,"
     " initiated_at       INTEGER,"
     " cpv_codes          TEXT NOT NULL DEFAULT '',"
     " countries          TEXT NOT NULL DEFAULT '',"
     " keywords           TEXT NOT NULL DEFAULT '',"
     " exclusions         TEXT NOT NULL DEFAULT '',"
     " description        TEXT NOT NULL DEFAULT '',"
     " described_by       TEXT NOT NULL DEFAULT '',"
     " described_at       INTEGER NOT NULL DEFAULT 0,"
     " described_version  INTEGER NOT NULL DEFAULT -1)"].

%% @doc Every change to the schema since 0.1.0, as {UserVersion, Statements}
%% in ascending order. Append only: a step a box has applied is never edited.
-spec migrations() -> [{pos_integer(), [string()]}].
migrations() ->
    [{1, ["ALTER TABLE tender_profiles ADD COLUMN archived_at INTEGER",
          "ALTER TABLE tender_profiles ADD COLUMN archived_by TEXT NOT NULL DEFAULT ''"]}].

-spec start_link(string()) -> {ok, pid()} | {error, term()}.
start_link(SqlitePath) ->
    gen_server:start_link({local, ?MODULE}, ?MODULE, SqlitePath, []).

%% @doc One parameterised write: ok, or {error, Reason}, which a projection
%% returns as {error, {store_error, Reason}} for evoq to retry.
-spec exec(string(), list()) -> ok | {error, term()}.
exec(Sql, Args) ->
    called({exec, Sql, Args}).

%% @doc One parameterised read, for tests and inspection.
-spec q(string(), list()) -> [list()] | {error, term()}.
q(Sql, Args) ->
    called({q, Sql, Args}).

%% The one try/catch here is the T8 boundary named in the moduledoc: the exit
%% of a call carries the request, so it is answered by name instead.
called(Request) ->
    try gen_server:call(?MODULE, Request, 5000)
    catch exit:_ -> {error, store_unavailable}
    end.

init(SqlitePath) ->
    ok = filelib:ensure_dir(SqlitePath),
    opened(esqlite3:open(SqlitePath)).

opened({ok, Conn}) -> schemed(Conn, migrated(Conn, create_schema(Conn, pragmas() ++ schema())));
opened({error, Reason}) -> {stop, {open_failed, Reason}}.

schemed(Conn, ok) -> {ok, #state{conn = Conn}};
schemed(_Conn, {error, Reason}) -> {stop, {schema_failed, Reason}}.

handle_call({exec, Sql, Args}, _From, #state{conn = Conn} = State) ->
    {reply, written(queried(Conn, Sql, Args)), State};
handle_call({q, Sql, Args}, _From, #state{conn = Conn} = State) ->
    {reply, queried(Conn, Sql, Args), State};
handle_call(_Request, _From, State) ->
    {reply, {error, unknown_request}, State}.

handle_cast(_Msg, State) -> {noreply, State}.

handle_info(_Info, State) -> {noreply, State}.

terminate(_Reason, _State) -> ok.

%% @doc What a crash report may show of this process: the SQL of the request
%% it was serving, never its arguments, and the stack without arguments.
-spec format_status(gen_server:format_status()) -> gen_server:format_status().
format_status(Status) ->
    maps:map(fun redacted/2, Status).

redacted(message, {Op, Sql, _Args}) -> {Op, Sql, redacted};
redacted(message, _Other) -> redacted;
redacted(reason, Reason) -> without_arguments(Reason);
redacted(log, _Log) -> [];
redacted(_Key, Value) -> Value.

without_arguments({Reason, [{_, _, _, _} | _] = Stack}) ->
    {without_arguments(Reason), [{M, F, arity(A), L} || {M, F, A, L} <- Stack]};
without_arguments(Reason) when is_atom(Reason) -> Reason;
without_arguments({Tag, _Detail}) when is_atom(Tag) -> Tag;
without_arguments(_Reason) -> redacted.

arity(Args) when is_list(Args) -> length(Args);
arity(Arity) -> Arity.

%% The T8 boundary inside the process (see the moduledoc): what esqlite raises
%% is answered as its reason alone, without the stack or the arguments.
queried(Conn, Sql, Args) ->
    try esqlite3:q(Conn, Sql, Args)
    catch Class:Reason -> {error, {sqlite_raised, Class, without_arguments(Reason)}}
    end.

%% WRITE-AHEAD LOG, so query_tenders' own connection reads while this one
%% writes, and a short wait rather than SQLITE_BUSY when they meet, which
%% would answer a reader store_unavailable for a lock held a millisecond.
%% WAL is a property of the file and stays set.
pragmas() ->
    ["PRAGMA journal_mode=WAL", "PRAGMA busy_timeout=2000"].

create_schema(Conn, [Sql | Rest]) -> next_ddl(esqlite3:exec(Conn, Sql), Conn, Rest);
create_schema(_Conn, []) -> ok.

next_ddl(ok, Conn, Rest) -> create_schema(Conn, Rest);
next_ddl({error, _} = E, _Conn, _Rest) -> E.

%% Each migration above the file's user_version, in order, one transaction
%% each: its statements and the version it brings the file to, or none of it.
migrated(Conn, ok) -> migrate(Conn, user_version(Conn), migrations());
migrated(_Conn, {error, _} = E) -> E.

user_version(Conn) ->
    [[Version]] = esqlite3:q(Conn, "PRAGMA user_version"),
    Version.

migrate(Conn, At, [{Version, _Statements} | Rest]) when Version =< At ->
    migrate(Conn, At, Rest);
migrate(Conn, _At, [{Version, Statements} | Rest]) ->
    stepped(esqlite3:exec(Conn, transaction(Version, Statements)), Conn, Version, Rest);
migrate(_Conn, _At, []) ->
    ok.

transaction(Version, Statements) ->
    lists:flatten(["BEGIN; ", [[S, "; "] || S <- Statements],
                   io_lib:format("PRAGMA user_version = ~b; COMMIT;", [Version])]).

stepped(ok, Conn, Version, Rest) ->
    migrate(Conn, Version, Rest);
stepped({error, _} = E, Conn, _Version, _Rest) ->
    _ = esqlite3:exec(Conn, "ROLLBACK"),
    E.

written([]) -> ok;
written({error, _} = E) -> E;
written(Rows) -> {error, {unexpected_rows, Rows}}.

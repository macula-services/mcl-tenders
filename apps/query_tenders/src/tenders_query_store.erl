%% @doc The QRY department's SQLite store: one gen_server owning one esqlite
%% connection to the file project_tenders writes.
%%
%% READ-ONLY BY API: only q/2 is exposed, so no query desk can write. The
%% schema is tenders_read_model_store's; this process opens the same file
%% after project_tenders has created it (query_tenders depends on
%% project_tenders).
%%
%% Its replies carry the profile, so it keeps them out of every report as the
%% writer does (tenders_read_model_store, T8): a raise is answered rather than
%% exited on, a crash report shows the SQL and never an argument, and a dead or
%% stuck store is answered `{error, store_unavailable}'.
-module(tenders_query_store).

-behaviour(gen_server).

-export([start_link/1, q/2]).
-export([init/1, handle_call/3, handle_cast/2, handle_info/2, terminate/2, format_status/1]).

-record(state, {conn :: esqlite3:esqlite3()}).

-spec start_link(string()) -> {ok, pid()} | {error, term()}.
start_link(SqlitePath) ->
    gen_server:start_link({local, ?MODULE}, ?MODULE, SqlitePath, []).

%% @doc One parameterised read: rows as lists of cells in SELECT order, or
%% {error, Reason}.
-spec q(string(), list()) -> [list()] | {error, term()}.
q(Sql, Args) ->
    try gen_server:call(?MODULE, {q, Sql, Args}, 5000)
    catch exit:_ -> {error, store_unavailable}
    end.

init(SqlitePath) ->
    opened(esqlite3:open(SqlitePath)).

%% The writer set the file to WAL; this connection waits for a lock rather
%% than answer SQLITE_BUSY, which a reader would see as store_unavailable.
opened({ok, Conn}) -> waiting(esqlite3:exec(Conn, "PRAGMA busy_timeout=2000"), Conn);
opened({error, Reason}) -> {stop, {open_failed, Reason}}.

waiting(ok, Conn) -> {ok, #state{conn = Conn}};
waiting({error, Reason}, _Conn) -> {stop, {pragma_failed, Reason}}.

handle_call({q, Sql, Args}, _From, #state{conn = Conn} = State) ->
    {reply, queried(Conn, Sql, Args), State};
handle_call(_Request, _From, State) ->
    {reply, {error, unknown_request}, State}.

handle_cast(_Msg, State) -> {noreply, State}.

handle_info(_Info, State) -> {noreply, State}.

terminate(_Reason, _State) -> ok.

%% @doc What a crash report may show of this process: the SQL it was serving,
%% never its arguments, and the stack without arguments.
-spec format_status(gen_server:format_status()) -> gen_server:format_status().
format_status(Status) ->
    maps:map(fun redacted/2, Status).

redacted(message, {q, Sql, _Args}) -> {q, Sql, redacted};
redacted(message, _Other) -> redacted;
redacted(reason, Reason) -> without_arguments(Reason);
redacted(log, _Log) -> [];
redacted(_Key, Value) -> Value.

%% What esqlite raises is answered as its reason alone (T8).
queried(Conn, Sql, Args) ->
    try esqlite3:q(Conn, Sql, Args)
    catch Class:Reason -> {error, {sqlite_raised, Class, without_arguments(Reason)}}
    end.

without_arguments({Reason, [{_, _, _, _} | _] = Stack}) ->
    {without_arguments(Reason), [{M, F, arity(A), L} || {M, F, A, L} <- Stack]};
without_arguments(Reason) when is_atom(Reason) -> Reason;
without_arguments({Tag, _Detail}) when is_atom(Tag) -> Tag;
without_arguments(_Reason) -> redacted.

arity(Args) when is_list(Args) -> length(Args);
arity(Arity) -> Arity.

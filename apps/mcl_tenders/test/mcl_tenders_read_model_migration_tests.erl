%%% @doc A box that ran 0.1.0 already has a read model. The store brings its
%%% schema forward in place on the next boot (PRAGMA user_version), keeping
%%% every row, and a second boot changes nothing. A step that fails leaves the
%%% file as it was and stops the store naming the step; a file from a newer
%%% release than this one is refused, not served (macula-services/mcl-tenders#15).
-module(mcl_tenders_read_model_migration_tests).

-include_lib("eunit/include/eunit.hrl").

%% The tender_profiles table exactly as 0.1.0 created it.
-define(SCHEMA_0_1_0,
        "CREATE TABLE tender_profiles ("
        " realm              TEXT PRIMARY KEY,"
        " initiated_at       INTEGER,"
        " cpv_codes          TEXT NOT NULL DEFAULT '',"
        " countries          TEXT NOT NULL DEFAULT '',"
        " keywords           TEXT NOT NULL DEFAULT '',"
        " exclusions         TEXT NOT NULL DEFAULT '',"
        " description        TEXT NOT NULL DEFAULT '',"
        " described_by       TEXT NOT NULL DEFAULT '',"
        " described_at       INTEGER NOT NULL DEFAULT 0,"
        " described_version  INTEGER NOT NULL DEFAULT -1)").

%% A step that fails partway: the file already has archived_by (a hand-made
%% change, say) but not archived_at, so step 1 adds archived_at and then fails
%% on archived_by. None of it may stay.
a_failed_step_leaves_the_file_as_it_was_and_names_the_step_test() ->
    Path = file_with("ALTER TABLE tender_profiles ADD COLUMN archived_by TEXT NOT NULL DEFAULT ''"),
    try
        ?assertMatch({error, {migration_failed, 1, #{errmsg := _}}}, started(Path)),
        {ok, Conn} = esqlite3:open(Path),
        ?assertEqual([[0]], esqlite3:q(Conn, "PRAGMA user_version")),
        Columns = [C || [_, C | _] <- esqlite3:q(Conn, "PRAGMA table_info(tender_profiles)")],
        ?assertNot(lists:member(<<"archived_at">>, Columns)),
        ok = esqlite3:close(Conn)
    after
        cleanup(Path)
    end.

%% An older image on a file a newer release brought forward (a rollback) does
%% not know that schema: it refuses to start, naming both versions.
a_file_from_a_newer_release_is_refused_test() ->
    Newer = lists:last([V || {V, _} <- tenders_read_model_store:migrations()]) + 1,
    Path = file_with(io_lib:format("PRAGMA user_version = ~b", [Newer])),
    try
        ?assertEqual({error, {schema_newer_than_release, Newer, Newer - 1}}, started(Path))
    after
        cleanup(Path)
    end.

%% start_link as its supervisor calls it, without taking the test down with it.
started(Path) ->
    Trap = process_flag(trap_exit, true),
    Result = tenders_read_model_store:start_link(Path),
    receive {'EXIT', _, _} -> ok after 1000 -> ok end,
    process_flag(trap_exit, Trap),
    Result.

file_with(Sql) ->
    Path = setup(),
    {ok, Conn} = esqlite3:open(Path),
    ok = esqlite3:exec(Conn, lists:flatten(Sql)),
    ok = esqlite3:close(Conn),
    Path.

migration_test_() ->
    {setup, fun setup/0, fun cleanup/1,
     fun(Path) ->
         [{timeout, 30, ?_test(a_0_1_0_read_model_is_brought_forward_keeping_its_rows(Path))},
          {timeout, 30, ?_test(a_second_boot_changes_nothing(Path))}]
     end}.

setup() ->
    {ok, _} = application:ensure_all_started(esqlite),
    Dir = filename:join(["/tmp", "mcl_tenders_read_model_migration_tests",
                         integer_to_list(erlang:unique_integer([positive]))]),
    Path = filename:join(Dir, "tenders.sqlite3"),
    ok = filelib:ensure_dir(Path),
    {ok, Conn} = esqlite3:open(Path),
    ok = esqlite3:exec(Conn, ?SCHEMA_0_1_0),
    ok = esqlite3:exec(Conn, "INSERT INTO tender_profiles (realm, initiated_at, countries,"
                             " described_version) VALUES ('5e', 7, 'BEL', 3)"),
    ok = esqlite3:close(Conn),
    Path.

cleanup(Path) ->
    _ = file:del_dir_r(filename:dirname(Path)),
    ok.

a_0_1_0_read_model_is_brought_forward_keeping_its_rows(Path) ->
    booted(Path, fun() ->
        ?assertEqual([[3]], tenders_read_model_store:q("PRAGMA user_version", [])),
        %% The morning list's table is there, empty, beside the kept profile.
        ?assertEqual([[0]], tenders_read_model_store:q("SELECT count(*) FROM tenders", [])),
        ?assertEqual([[<<"5e">>, 7, <<"BEL">>, 3, undefined, <<>>]],
                     tenders_read_model_store:q(
                       "SELECT realm, initiated_at, countries, described_version, archived_at,"
                       " archived_by FROM tender_profiles", []))
    end).

a_second_boot_changes_nothing(Path) ->
    booted(Path, fun() ->
        ?assertEqual([[3]], tenders_read_model_store:q("PRAGMA user_version", [])),
        ?assertEqual([[<<"5e">>, undefined]],
                     tenders_read_model_store:q("SELECT realm, archived_at FROM tender_profiles", []))
    end).

booted(Path, Check) ->
    {ok, Pid} = tenders_read_model_store:start_link(Path),
    unlink(Pid),
    try Check()
    after
        Ref = monitor(process, Pid),
        exit(Pid, shutdown),
        receive {'DOWN', Ref, process, Pid, _} -> ok end
    end.

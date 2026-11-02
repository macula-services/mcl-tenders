%%% @doc A box that ran 0.1.0 already has a read model. The store brings its
%%% schema forward in place on the next boot (PRAGMA user_version), keeping
%%% every row, and a second boot changes nothing.
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
        ?assertEqual([[2]], tenders_read_model_store:q("PRAGMA user_version", [])),
        %% The morning list's table is there, empty, beside the kept profile.
        ?assertEqual([[0]], tenders_read_model_store:q("SELECT count(*) FROM tenders", [])),
        ?assertEqual([[<<"5e">>, 7, <<"BEL">>, 3, undefined, <<>>]],
                     tenders_read_model_store:q(
                       "SELECT realm, initiated_at, countries, described_version, archived_at,"
                       " archived_by FROM tender_profiles", []))
    end).

a_second_boot_changes_nothing(Path) ->
    booted(Path, fun() ->
        ?assertEqual([[2]], tenders_read_model_store:q("PRAGMA user_version", [])),
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

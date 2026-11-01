%% @doc Which registry tags each push publishes, asserted locally.
%%
%% `:latest' is what anyone outside the fleet pulls, and what
%% deploy/docker-compose.yml runs. It must name a signed release and never an
%% unreviewed tip of main (macula-services/mcl-jobs#9). The tag list comes from
%% scripts/image_tags.sh, so this suite runs that script for each kind of ref
%% build-push.yml can see; and it reads the workflow, so the one job that does
%% move `:latest' stays behind the v* tag and the signature.
-module(mcl_tenders_image_channels_tests).

-include_lib("eunit/include/eunit.hrl").

-define(IMAGE, "ghcr.io/macula-services/mcl-tenders").
-define(SHA, "e33a0f2c0ffee0000000000000000000000000ab").

%% A push to main publishes the tip for trying, under :main and :<sha>, and
%% nothing anybody follows.
main_publishes_main_and_its_sha_and_never_latest_test() ->
    ?assertEqual({0, "tags=" ?IMAGE ":main " ?IMAGE ":" ?SHA},
                 tags("refs/heads/main")).

%% A v* tag publishes its version ONLY. :latest moves later, in
%% promote-latest, once attest has signed this digest.
a_release_tag_publishes_its_version_only_test() ->
    ?assertEqual({0, "tags=" ?IMAGE ":0.4.1"}, tags("refs/tags/v0.4.1")).

%% workflow_dispatch can run from any branch; a branch build must publish
%% nothing at all, and say why.
any_other_ref_is_refused_naming_it_test() ->
    {Status, Out} = tags("refs/heads/some-branch"),
    ?assertNotEqual(0, Status),
    ?assertNotEqual(nomatch, string:find(Out, "refs/heads/some-branch")),
    ?assertEqual(nomatch, string:find(Out, "tags=")).

%% The workflow takes its tags from the script, so the cases above are the
%% ones that ship.
the_workflow_sets_its_tags_from_the_script_test() ->
    ?assertMatch({match, _}, re:run(workflow(), "scripts/image_tags\\.sh")).

%% :latest appears in exactly one job, promote-latest. That job runs only for
%% a v* tag, and only after attest.
only_promote_latest_moves_latest_and_only_after_a_signed_release_test() ->
    Jobs = jobs(workflow()),
    ?assertEqual(["promote-latest"],
                 [Name || {Name, Body} <- Jobs, mentions_latest(Body)]),
    Promote = proplists:get_value("promote-latest", Jobs),
    ?assertMatch({match, _}, re:run(Promote, "^    needs: \\[build-and-push, attest\\]$", [multiline])),
    ?assertMatch({match, _}, re:run(Promote, "^    if: startsWith\\(github\\.ref, 'refs/tags/v'\\)", [multiline])).

%% :latest NEVER MOVES BACKWARDS. Tags build in parallel and finish in any
%% order, so only the newest v* by VERSION order promotes (v0.10.0 is newer
%% than v0.9.0), and an older one, a late patch to an older line included,
%% leaves :latest alone.
only_the_newest_release_moves_latest_test() ->
    Repo = repo_with_tags(["v0.4.0", "v0.5.0", "v0.9.0", "v0.10.0", "v0.4.1"]),
    try
        ?assertEqual({0, "promote=true"}, newest(Repo, "v0.10.0")),
        ?assertEqual({0, "promote=false"}, newest(Repo, "v0.4.1")),
        ?assertEqual({0, "promote=false"}, newest(Repo, "v0.9.0")),
        ?assertEqual({0, "promote=false"}, newest(Repo, "v0.5.0"))
    after
        file:del_dir_r(Repo)
    end.

%% And the workflow asks it, with every tag fetched, one promotion at a time.
promote_latest_is_serialised_and_asks_whether_it_is_newest_test() ->
    Promote = proplists:get_value("promote-latest", jobs(workflow())),
    ?assertMatch({match, _}, re:run(Promote, "^    concurrency:\\n      group: promote-latest\\n"
                                             "      cancel-in-progress: false$", [multiline])),
    ?assertMatch({match, _}, re:run(Promote, "git fetch --force --tags origin\\n\\s+"
                                             "scripts/is_newest_release\\.sh ", [multiline])),
    ?assertMatch({match, _}, re:run(Promote, "- name: Point :latest at the signed digest\\n"
                                             "        if: steps\\.newest\\.outputs\\.promote == 'true'$",
                                    [multiline])).

%% No image while the service's own tests are red: the build waits on them.
the_build_waits_on_the_tests_test() ->
    Build = proplists:get_value("build-and-push", jobs(workflow())),
    ?assertMatch({match, _}, re:run(Build, "^    needs: \\[guard, test\\]$", [multiline])).

%%------------------------------------------------------------------------------

tags(Ref) ->
    run("GITHUB_REF=" ++ Ref ++ " GITHUB_SHA=" ++ ?SHA ++ " sh "
        ++ alongside("scripts/image_tags.sh") ++ " 2>&1").

%% Output and exit status of a shell command.
run(Cmd0) ->
    Cmd = Cmd0 ++ "; echo \"exit=$?\"",
    Lines = string:split(string:trim(os:cmd(Cmd)), "\n", all),
    {Body, ["exit=" ++ Status]} = lists:split(length(Lines) - 1, Lines),
    {list_to_integer(Status), lists:flatten(lists:join("\n", Body))}.

%% A throwaway repository, one commit per tag, tagged in the order given.
repo_with_tags(Tags) ->
    Repo = filename:join(["/tmp", "mcl_tenders_image_channels_tests",
                          integer_to_list(erlang:unique_integer([positive]))]),
    ok = filelib:ensure_path(Repo),
    Git = "git -C " ++ Repo ++ " -c user.name=test -c user.email=test@example.invalid ",
    _ = os:cmd(Git ++ "init -q"),
    [os:cmd(Git ++ "commit -q --allow-empty -m " ++ T ++ " && " ++ Git ++ "tag " ++ T) || T <- Tags],
    Repo.

newest(Repo, Tag) ->
    run("cd " ++ Repo ++ " && sh " ++ alongside("scripts/is_newest_release.sh") ++ " " ++ Tag
        ++ " 2>/dev/null").

workflow() ->
    {ok, Text} = file:read_file(alongside(".github/workflows/build-push.yml")),
    binary_to_list(Text).

%% The top-level jobs, each with its own text up to the next job. Comments go,
%% so a job explaining :latest is not taken for one moving it.
jobs(Text) ->
    [_, After] = string:split(Text, "\njobs:\n"),
    Code = [L || L <- string:split(After, "\n", all), not is_comment(L)],
    split_jobs(Code, []).

split_jobs([], Acc) -> lists:reverse(Acc);
split_jobs(["  " ++ [C | _] = Line | Rest], Acc) when C =/= $\s ->
    Name = string:trim(Line, trailing, ":"),
    {Body, Next} = lists:splitwith(fun(L) -> not is_job_line(L) end, Rest),
    split_jobs(Next, [{string:trim(Name), lists:flatten(lists:join("\n", Body))} | Acc]);
split_jobs([_ | Rest], Acc) -> split_jobs(Rest, Acc).

is_job_line("  " ++ [C | _]) -> C =/= $\s;
is_job_line(_) -> false.

is_comment(Line) -> lists:prefix("#", string:trim(Line, leading)).

mentions_latest(Body) -> string:find(Body, ":latest") =/= nomatch.

%% Relative to the beam rather than the working directory, as in
%% mcl_tenders_service_tests.
alongside(Name) -> climb(filename:dirname(code:which(?MODULE)), Name, 8).

climb(_Dir, Name, 0) -> Name;
climb(Dir, Name, Left) ->
    Candidate = filename:join(Dir, Name),
    found(filelib:is_regular(Candidate), Candidate, Dir, Name, Left).

found(true, Candidate, _Dir, _Name, _Left) -> Candidate;
found(false, _Candidate, Dir, Name, Left) ->
    climb(filename:dirname(Dir), Name, Left - 1).

%% @doc A known-vulnerable dependency cannot ship, asserted locally.
%%
%% The advisory scan is macula-ci-images' shared dependency-advisories
%% workflow, called from lint.yml, so it runs on every change and a red
%% dependency shows before a tag (macula-services/mcl-jobs#6). It is a gate only while the
%% release waits on it: build-and-push needs the `test' job, which calls
%% lint.yml. This suite reads both workflows and holds them to that.
-module(mcl_tenders_advisories_tests).

-include_lib("eunit/include/eunit.hrl").

%% The shared workflow, pinned by full commit sha: a reusable workflow runs in
%% the caller's repository, and a moving ref would let the check change under
%% the same commit.
lint_calls_the_shared_scan_pinned_by_commit_test() ->
    Job = advisories_job(),
    ?assertMatch({match, _},
                 re:run(Job, "^    uses: macula-io/macula-ci-images/\\.github/workflows/"
                             "dependency-advisories\\.yml@[0-9a-f]{40}$", [multiline])).

%% This repository builds Erlang only, so Erlang is what it scans.
it_scans_the_erlang_build_test() ->
    ?assertMatch({match, _}, re:run(advisories_job(), "^      ecosystem: erlang$", [multiline])).

%% The toolchain is the image, pinned by digest, and the job runs as a user,
%% never root (the shared workflow refuses uid 0).
it_runs_in_a_digest_pinned_image_as_a_user_test() ->
    Job = advisories_job(),
    ?assertMatch({match, _},
                 re:run(Job, "^      container: ghcr\\.io/macula-io/macula-ci-otp:\\S+@sha256:[0-9a-f]{64}$",
                        [multiline])),
    {match, [Uid]} = re:run(Job, "^      container-options: '--user ([0-9]+):[0-9]+'$",
                            [multiline, {capture, all_but_first, list}]),
    ?assertNotEqual("0", Uid).

%% It runs wherever lint runs: every push to main and every pull request.
it_runs_on_every_change_test() ->
    Lint = workflow("lint.yml"),
    ?assertMatch({match, _}, re:run(Lint, "^  pull_request:", [multiline])),
    ?assertMatch({match, _}, re:run(Lint, "^  push:\\n    branches: \\[main\\]", [multiline])).

%% The release waits on it: build-and-push needs `test', and `test' is lint.yml.
the_release_waits_on_the_scan_test() ->
    Jobs = jobs(workflow("build-push.yml")),
    ?assertMatch({match, _}, re:run(proplists:get_value("test", Jobs),
                                    "^    uses: \\./\\.github/workflows/lint\\.yml$", [multiline])),
    ?assertMatch({match, _}, re:run(proplists:get_value("build-and-push", Jobs),
                                    "^    needs: \\[[^]]*\\btest\\b[^]]*\\]$", [multiline])).

%%------------------------------------------------------------------------------

advisories_job() ->
    Jobs = jobs(workflow("lint.yml")),
    ?assert(lists:keymember("advisories", 1, Jobs)),
    proplists:get_value("advisories", Jobs).

workflow(Name) ->
    {ok, Text} = file:read_file(alongside(".github/workflows/" ++ Name)),
    binary_to_list(Text).

%% The top-level jobs, each with its own text up to the next job; comments go.
jobs(Text) ->
    [_, After] = string:split(Text, "\njobs:\n"),
    Code = [L || L <- string:split(After, "\n", all), not is_comment(L)],
    split_jobs(Code, []).

split_jobs([], Acc) -> lists:reverse(Acc);
split_jobs([Line | Rest], Acc) ->
    split_jobs(is_job_line(Line), Line, Rest, Acc).

split_jobs(true, Line, Rest, Acc) ->
    {Body, Next} = lists:splitwith(fun(L) -> not is_job_line(L) end, Rest),
    Name = string:trim(string:trim(Line, trailing, ":")),
    split_jobs(Next, [{Name, lists:flatten(lists:join("\n", Body))} | Acc]);
split_jobs(false, _Line, Rest, Acc) ->
    split_jobs(Rest, Acc).

is_job_line("  " ++ [C | _]) -> C =/= $\s;
is_job_line(_) -> false.

is_comment(Line) -> lists:prefix("#", string:trim(Line, leading)).

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

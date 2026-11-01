%%% @doc The version sites, asserted against each other.
%%%
%%% The version a peer reads off the mesh (info/0), the OTP application's vsn
%%% and the relx release the image ships are one number written in three
%%% files, and nothing in the build reads them together. A sibling service
%%% (mcl-news 0.2.0) went out with its release string a version behind for
%%% exactly that reason, while every other test stayed green.
-module(mcl_tenders_release_files_tests).

-include_lib("eunit/include/eunit.hrl").

-define(APP, mcl_tenders).
-define(SERVICE, mcl_tenders_service).

the_versions_agree_test() ->
    #{version := Reported} = ?SERVICE:info(),
    _ = application:load(?APP),
    {ok, App} = application:get_key(?APP, vsn),
    {match, [Release]} = re:run(read("rebar.config"),
                                <<"\\{release, \\{mcl_tenders, \"([^\"]+)\"\\}">>,
                                [{capture, all_but_first, binary}]),
    ?assertEqual({Reported, Reported}, {list_to_binary(App), Release}).

%% ghcr links the package to the repository this label names, and the image
%% is named after the release, not the repository: a label copied from the
%% image name points at a repository that does not exist.
the_image_names_its_source_repository_test() ->
    ?assertMatch({match, _},
                 re:run(read("Containerfile"),
                        <<"image\\.source=\"https://github\\.com/macula-services/mcl-tenders\"">>)).

%% NO ERLANG DISTRIBUTION (T2, T8; macula-services/mcl-om#24). A node that
%% listens for node connections, with a cookie this public repository names,
%% lets anyone who reaches the box attach and read the profile and the node
%% key. So: no long name, no cookie, no epmd, no listener.
the_node_takes_no_node_connections_test() ->
    VmArgs = read("config/vm.args.src"),
    ?assertEqual(nomatch, re:run(VmArgs, <<"^-(name|setcookie)\\b">>, [multiline])),
    ?assertMatch({match, _}, re:run(VmArgs, <<"^-start_epmd false$">>, [multiline])),
    ?assertMatch({match, _}, re:run(VmArgs, <<"^-dist_listen false$">>, [multiline])).

%% The image and the compose name no cookie, and the image writes no crash
%% dump, which would copy the heaps the profile passes through.
no_cookie_is_published_and_no_crash_dump_is_written_test() ->
    [?assertEqual({File, nomatch}, {File, re:run(read(File), <<"MCL_COOKIE|setcookie">>)})
     || File <- ["Containerfile", "deploy/docker-compose.yml", "README.md"]],
    ?assertMatch({match, _}, re:run(read("Containerfile"), <<"^ENV ERL_CRASH_DUMP_SECONDS=0$">>, [multiline])).

%% Nothing in the service needs distribution: a call that would is a sign the
%% posture above was broken by a later change.
no_module_uses_distributed_erlang_test() ->
    Sources = filelib:wildcard(filename:join(filename:dirname(read_path("rebar.config")), "apps/*/src/**/*.erl")),
    ?assertNotEqual([], Sources),
    ?assertEqual([], [S || S <- Sources,
                           {ok, Bin} <- [file:read_file(S)],
                           re:run(Bin, <<"\\b(net_kernel|erpc|rpc|global|pg):|\\bnodes\\(">>) =/= nomatch]).

read_path(Name) -> alongside(Name).

%% The README shows this service's own logo, both themes, and not the generic
%% Macula one a copied template brings along.
the_readme_shows_the_tenders_logo_test() ->
    Readme = read("README.md"),
    [begin
         ?assertMatch({File, {match, _}}, {File, re:run(Readme, <<"\"assets/", File/binary, "\"">>)}),
         ?assertMatch({File, {match, _}}, {File, re:run(read("assets/" ++ binary_to_list(File)), <<">TENDERS<">>)})
     end || File <- [<<"macula-tenders-full-light.svg">>, <<"macula-tenders-full-dark.svg">>]],
    ?assertEqual(nomatch, re:run(Readme, <<"assets/macula-full-">>)).

%% Relative to the beam rather than the working directory, because eunit runs
%% from wherever the developer happens to be standing.
read(Name) ->
    {ok, Text} = file:read_file(alongside(Name)),
    Text.

alongside(Name) -> climb(filename:dirname(code:which(?MODULE)), Name, 8).

climb(_Dir, Name, 0) -> Name;
climb(Dir, Name, Left) ->
    Candidate = filename:join(Dir, Name),
    found(filelib:is_regular(Candidate), Candidate, Dir, Name, Left).

found(true, Candidate, _Dir, _Name, _Left) -> Candidate;
found(false, _Candidate, Dir, Name, Left) ->
    climb(filename:dirname(Dir), Name, Left - 1).

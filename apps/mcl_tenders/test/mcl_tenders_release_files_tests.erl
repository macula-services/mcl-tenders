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

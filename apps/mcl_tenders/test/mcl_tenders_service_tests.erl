%% @doc The service contract, asserted locally.
%%
%% mcl_om resolves its six callbacks BY NAME at startup, on a live node, so a
%% service that forgets one dies with `undef' where nobody is watching. The
%% primary defence is the `-behaviour(mcl_om_service)' attribute on the
%% service module, which turns a missing callback into a compile error under
%% warnings_as_errors.
%%
%% What this suite adds is everything the compiler cannot see: that the attribute
%% has not been quietly dropped, that the values inside those callbacks are the
%% shapes mcl_om will destructure, and that the names and version this service
%% reports are the ones it actually has. Nothing local boots mcl_om, so
%% asserting the shape by hand is the closest available thing to a rehearsal.
-module(mcl_tenders_service_tests).

-include_lib("eunit/include/eunit.hrl").

-define(APP, mcl_tenders).
-define(SERVICE, mcl_tenders_service).

%% Belt and braces with the behaviour attribute, and it survives the attribute
%% being removed. If mcl_om ever adds a SEVENTH required callback this test
%% keeps passing and the deploy still breaks, which is the honest limit of a
%% local assertion about a remote contract.
exports_every_required_callback_test() ->
    _ = code:ensure_loaded(?SERVICE),
    Required = [{info, 0}, {start, 1}, {stop, 1},
                {health, 0}, {capabilities, 0}, {identity_spec, 0}],
    Missing = [F || {N, A} = F <- Required,
                    not erlang:function_exported(?SERVICE, N, A)],
    ?assertEqual([], Missing).

%% THE ATTRIBUTE ITSELF. Dropped to silence a warning, it would leave compile
%% and the export check above green, and the next callback mcl_om requires
%% would be an `undef' at boot instead of a compile error.
declares_the_mcl_om_service_behaviour_test() ->
    Attrs = ?SERVICE:module_info(attributes),
    ?assert(lists:member(mcl_om_service, proplists:get_value(behaviour, Attrs, []))).

info_carries_the_three_keys_test() ->
    #{name := Name, version := Vsn, description := Desc} = ?SERVICE:info(),
    ?assert(is_binary(Name)),
    ?assert(is_binary(Vsn)),
    ?assert(is_binary(Desc)),
    ?assertEqual(<<"mcl-tenders">>, Name).

%% THE TWO NAMES MUST AGREE. The OTP application is snake_case because it is an
%% Erlang atom; the repository, the container image and the name this service
%% answers to on the mesh are kebab-case. They describe one service, so a
%% scaffold generated with a mismatched pair is caught here on the first eunit
%% run rather than by a puzzled reader months later.
mesh_name_matches_the_application_test() ->
    #{name := Wire} = ?SERVICE:info(),
    Snake = atom_to_binary(?APP, utf8),
    ?assertEqual(binary:replace(Snake, <<"_">>, <<"-">>, [global]), Wire).

%% The version in info/0 is what a peer reads off /health, so it disagreeing with
%% the application it describes is a lie that nothing else would catch.
info_version_matches_the_application_test() ->
    _ = application:load(?APP),
    {ok, Vsn} = application:get_key(?APP, vsn),
    #{version := Reported} = ?SERVICE:info(),
    ?assertEqual(list_to_binary(Vsn), Reported).

health_is_green_test() ->
    ?assertEqual(ok, ?SERVICE:health()).

%% The profile's three procedures and nothing else, each served by a module that
%% implements macula_response. Changing the list breaks this test on purpose.
%%
%% T2, as declared: every one admits the tenders role only, `{callers, role}',
%% and requires a sealed call. mcl_tenders_callers_tests runs macula's own gate
%% on that declaration.
announces_the_procedures_for_the_tenders_role_only_test() ->
    Caps = without_org_key(fun ?SERVICE:capabilities/0),
    ?assertEqual([<<"describe_tender_profile">>, <<"get_tender_profile">>, <<"archive_tender_profile">>,
                  <<"get_tenders_page">>, <<"get_tender_by_id">>, <<"dismiss_tender">>],
                 [N || #{name := N} <- Caps]),
    ?assertEqual([required], lists:usort([maps:get(confidential, C, absent) || C <- Caps])),
    ?assertEqual([{callers, role}], lists:usort([maps:get(auth, C, absent) || C <- Caps])),
    [?assert(lists:member({behaviour, [macula_response]}, M:module_info(attributes)))
     || #{handler := {M, _}} <- Caps].

identity_spec_has_the_shape_mcl_om_expects_test() ->
    #{scope := Scope, actions := Actions,
      resources := Resources, ttl_days := Ttl} = ?SERVICE:identity_spec(),
    ?assert(is_binary(Scope)),
    ?assert(is_list(Actions)),
    ?assert(is_list(Resources)),
    ?assert(is_integer(Ttl) andalso Ttl > 0).

%% Once the org key id is known, the tenders group's distributor is announced
%% too: sealed calls only, and the handler decides, since the group a pull
%% names travels inside the sealed payload where no gate sees it.
announces_the_group_keys_once_the_org_key_is_known_test() ->
    Caps = with_env([{"MCL_GROUP_ORG_KEY_ID", lists:duplicate(64, $a)}], fun ?SERVICE:capabilities/0),
    [GroupKeys] = [C || #{name := <<"group_keys_v1">>} = C <- Caps],
    ?assertMatch(#{auth := handler_authorizes, confidential := required,
                   handler := {mcl_tenders_group_keys_pull, []}}, GroupKeys),
    ?assert(lists:member({behaviour, [macula_response]},
                         mcl_tenders_group_keys_pull:module_info(attributes))).

%% The setup the group waits on is in /health's info, as a state and never a
%% value, while the verdict stays green.
info_says_whether_the_group_is_set_up_test() ->
    ?assertEqual(unset, without_org_key(fun() -> maps:get(sealing, ?SERVICE:info()) end)),
    ?assertEqual(set, with_env([{"MCL_GROUP_ORG_KEY_ID", lists:duplicate(64, $a)},
                                {"MCL_TENDERS_GROUP_UCAN", "a-token"}],
                               fun() -> maps:get(sealing, ?SERVICE:info()) end)).

%% The morning list's process manager listens to the sensor's sealed fact,
%% from the realm's mcl-tenders org only, admitted by the group's token -- and
%% only once the group is set up: before, nothing is declared, so a setup
%% state never holds /health degraded. mcl_om's own check accepts it, and the
%% declaration names the admission, never a token.
subscribes_the_process_manager_once_the_group_is_set_up_test() ->
    ?assertEqual([], without_org_key(fun ?SERVICE:subscriptions/0)),
    Old = application:get_env(sense_tender_notices, realm_name),
    ok = application:set_env(sense_tender_notices, realm_name, <<"io.example">>),
    try
        Subs = with_env([{"MCL_GROUP_ORG_KEY_ID", lists:duplicate(64, $a)},
                         {"MCL_TENDERS_GROUP_UCAN", "canary-token-ab12"}],
                        fun ?SERVICE:subscriptions/0),
        ?assertMatch([#{topic := <<"io.example/mcl-tenders/tenders/", _/binary>>,
                        module := on_tender_notice_reported_v1_maybe_spot_tender,
                        sources := {org, <<"mcl-tenders">>},
                        group := <<"io.example/mcl-tenders/tenders">>,
                        admission := {tender_notices_group, admission, []}}], Subs),
        ?assertEqual(ok, mcl_om_pubsub_subscriptions:validate(Subs)),
        ?assertEqual(nomatch, binary:match(term_to_binary(Subs), <<"canary-token-ab12">>))
    after
        restore_app_env(Old)
    end.

restore_app_env(undefined) -> application:unset_env(sense_tender_notices, realm_name);
restore_app_env({ok, V}) -> application:set_env(sense_tender_notices, realm_name, V).

without_org_key(Fun) ->
    with_env([{"MCL_GROUP_ORG_KEY_ID", ""}, {"MCL_TENDERS_GROUP_UCAN", ""}], Fun).

with_env(Vars, Fun) ->
    Old = [{K, os:getenv(K)} || {K, _} <- Vars],
    [os:putenv(K, V) || {K, V} <- Vars],
    try Fun() after [restore(K, V) || {K, V} <- Old] end.

restore(K, false) -> os:unsetenv(K);
restore(K, V) -> os:putenv(K, V).

%% Its procedures are CALLs under the org-wide provider grant, and its one fact
%% travels sealed under the tenders group, so it asks the realm for no topic
%% authority.
asks_for_no_topic_authority_test() ->
    #{actions := Actions, resources := Resources} = ?SERVICE:identity_spec(),
    ?assertEqual([], Actions),
    ?assertEqual([], Resources).

%% The distributor, then the sensor. Without the group's setup the
%% distributor is not started (`ignore') and the sensor stays idle: started
%% here without mcl_om, it asks TED nothing and the tree stands.
%% T5, T12: /health shows the day's intake and how the sensor is, as counts,
%% tags and times, and the body stays JSON (mcl_om encodes it with jsx).
health_info_shows_the_intake_and_the_sensor_test() ->
    persistent_term:erase(sense_ted_notices),
    #{intake := unavailable, sensor := unavailable, quiet := 1} = Down = ?SERVICE:info(),
    ?assert(is_binary(jsx:encode(Down))),
    Now = erlang:system_time(millisecond),
    {ok, Pid} = tender_intake:start_link(),
    unlink(Pid),
    try
        ok = tender_intake:admit(),
        persistent_term:put(sense_ted_notices,
                            {ok, #{state => sweeping, idle_reason => none, last_swept_at => Now}}),
        Up = ?SERVICE:info(),
        ?assertMatch(#{intake := #{spotted := 1, dropped := 0, cap := 500, last_notice_at := 0},
                       sensor := #{state := sweeping, idle_reason := none, last_swept_at := Now},
                       quiet := 0}, Up),
        ?assert(is_binary(jsx:encode(Up))),
        %% Idle: the reason's tag only, never its detail.
        persistent_term:put(sense_ted_notices,
                            {ok, #{state => idle, idle_reason => {sealing_unset, ["MCL_TENDERS_GROUP_UCAN"]},
                                   last_swept_at => Now}}),
        ?assertMatch(#{sensor := #{idle_reason := sealing_unset}, quiet := 1}, ?SERVICE:info()),
        %% Sweeping, but no whole sweep in a day: quiet.
        persistent_term:put(sense_ted_notices,
                            {ok, #{state => sweeping, idle_reason => none,
                                   last_swept_at => Now - 25 * 3600 * 1000}}),
        ?assertMatch(#{quiet := 1}, ?SERVICE:info())
    after
        persistent_term:erase(sense_ted_notices),
        stopped(Pid)
    end.

%% Waits for the process to be gone, so the next start of its name cannot race it.
stopped(Pid) ->
    Ref = monitor(process, Pid),
    exit(Pid, shutdown),
    receive {'DOWN', Ref, process, Pid, _} -> ok after 5000 -> error({still_alive, Pid}) end.

%% The day's intake starts before the sensor, so the first notice is counted.
supervisor_starts_the_distributor_the_intake_and_the_sensor_test() ->
    {ok, {_Flags, Children}} = mcl_tenders_sup:init([]),
    ?assertEqual([mcl_tenders_group_keys, tender_intake, sense_ted_notices],
                 [maps:get(id, C) || C <- Children]),
    without_org_key(fun() ->
        {ok, Pid} = mcl_tenders_sup:start_link(),
        ?assertMatch([{sense_ted_notices, P, worker, _}, {tender_intake, I, worker, _},
                      {mcl_tenders_group_keys, undefined, worker, _}]
                       when is_pid(P) andalso is_pid(I), supervisor:which_children(Pid)),
        unlink(Pid),
        stopped(Pid)
    end).

%% The release takes the realm name from the environment: the fact topic and
%% the group carry it, and start/1 checks it against the realm tag.
release_config_names_the_realm_test() ->
    {ok, Text} = file:read_file(alongside("config/sys.config.src")),
    Named = re:replace(Text, <<"\"\\$\\{([A-Z_]+)\\}\"">>, <<"\"\\1\"">>, [global]),
    Substituted = re:replace(Named, <<"\\$\\{[A-Z_]+\\}">>, <<"0">>, [global, {return, list}]),
    {ok, Tokens, _End} = erl_scan:string(Substituted),
    {ok, Config} = erl_parse:parse_term(Tokens),
    Sensor = proplists:get_value(sense_tender_notices, Config, []),
    ?assertEqual("MCL_REALM_NAME", proplists:get_value(realm_name, Sensor)).

%%==============================================================================
%% The config the store cannot boot without
%%==============================================================================

%% ⚠ A SIBLING SERVICE'S FLEET CRASH-LOOPED ON TWO OF THREE NODES FOR WANT OF THE
%% `evoq' BLOCK.
%%
%% mcl_tenders_app opens the store AND a per-store evoq subscription before
%% `mcl_om:boot/1'. That subscription reads through evoq, which raises
%% `{not_configured, event_store_adapter}' unless sys.config names the adapter,
%% and evoq starts as a release-boot application before any service's `start/2'
%% runs, so nothing can inject it later.
%%
%% This reads the shipped config template, because the failure is a MISSING BLOCK
%% and no amount of exercising the code can notice something that is not there.
%% It compares the Erlang side of a boundary against the config side, which is
%% what neither side's own tests can do.
the_evoq_adapter_is_configured_wherever_a_store_is_opened_test() ->
    {ok, Text} = file:read_file(alongside("config/sys.config.src")),
    ?assert(erlang:function_exported(?SERVICE, event_store, 0)),
    lists:foreach(
      fun(Needed) ->
              ?assertNotEqual(nomatch, binary:match(Text, Needed),
                              {missing_from_sys_config, Needed})
      end,
      [<<"{evoq,">>, <<"event_store_adapter">>, <<"subscription_adapter">>,
       <<"reckon_evoq_adapter">>]).

%% ⚠ AND THE STORE ID IS IN TWO PLACES, WHICH IS ONE MORE THAN IT SHOULD BE.
%% `event_store/0''s `id' is what mcl_tenders_app opens; the `{store_id, ...}' in the evoq block
%% is what evoq falls back to when it resolves a dispatch before knowing there is
%% none. Nothing makes them agree, and disagreeing opens one store and addresses
%% another. Same boundary guard, other side.
the_store_id_agrees_between_erlang_and_config_test() ->
    {ok, Text} = file:read_file(alongside("config/sys.config.src")),
    Declared = atom_to_binary(maps:get(id, ?SERVICE:event_store()), utf8),
    ?assertNotEqual(nomatch, binary:match(Text, Declared),
                    {store_id_not_in_sys_config, Declared}).

%% And a third place: each CMD division dispatches into the store by name. A
%% division addressing any other id would persist nowhere this service opened.
every_division_dispatches_into_the_store_this_service_opens_test() ->
    Opened = maps:get(id, ?SERVICE:event_store()),
    ?assertEqual(Opened, tender_profile_aggregate:store_id()).

%% The read model lives beside the event store, under the same directory.
the_read_model_lives_beside_the_event_store_test() ->
    ?assertEqual(filename:join(maps:get(dir, ?SERVICE:event_store()), "tenders.sqlite3"),
                 project_tenders_sup:sqlite_path()).

%% The data directory must be somewhere, and a laptop default is fine. What is
%% not fine is shipping that default to a node, which is why the generated
%% compose file mounts a volume and sets the variable this reads.
the_data_directory_is_answerable_test() ->
    Dir = maps:get(dir, ?SERVICE:event_store()),
    ?assert(is_list(Dir)),
    ?assertNotEqual("", Dir).

%% ⚠ NOT THE OLD CONTRACT'S NAMES. mcl_om warns at every boot about a service
%% module exporting store_id/0 and data_dir/0 together, the shape of a service
%% built before 0.35; this one opens its own store and must not look like one.
no_old_store_callbacks_are_exported_test() ->
    ?assertEqual([], mcl_om:leftover_store_callbacks(?SERVICE)).
%%==============================================================================
%% The runtime is pinned in two places, and neither is the one you are running
%%==============================================================================

%% ⚠ THIS GUARD EXISTS BECAUSE A SIBLING SERVICE DID NOT HAVE IT, AND IT COST
%% THREE COMMITS AND AN IMAGE THAT SHIPPED ANYWAY.
%%
%% Its `Containerfile' said 27 while development ran on 28. So `rebar3 eunit'
%% passing locally meant "passing on 28" and nothing more, CI failed on a crash
%% that does not occur on 28 at all, and because the image build is a separate
%% workflow the image went to the fleet regardless.
%%
%% The release is pinned in TWO files, and the version actually running is a
%% third thing that agrees with neither by default. **A comment in each file
%% saying they must match is not a mechanism**, and both files carried one.
%%
%% ⚠⚠ IT FAILS RATHER THAN WARNS WHEN YOUR VM DIFFERS, AND THAT IS DELIBERATE.
%% Developing on a release you do not ship makes a green suite mean less than it
%% appears to. If you want to work on another release, move both pins and find
%% out what breaks, which is the whole point of having them.
%%
%% ⚠ TO THE PATCH, AND NOTHING FLOATS. This compared majors only, so when Docker
%% Hub moved the floating `erlang:28-alpine' on 2026-09-22 a service generated
%% from this template shipped OTP 28.5 and its guard stayed green. An image's
%% tag need not name a release, so the builder stage and lint each ASSERT one
%% in a check step; this compares those, .tool-versions and this VM, to the
%% patch.
the_runtime_agrees_between_the_image_the_ci_and_this_vm_test() ->
    Check = "\\{<<\"([0-9]+\\.[0-9]+\\.[0-9]+)\">>, true\\} -> halt\\(0\\);",
    Image = pinned("Containerfile", Check),
    CiCheck = pinned(".github/workflows/lint.yml", Check),
    Tools = pinned(".tool-versions", "^erlang ([0-9]+\\.[0-9]+\\.[0-9]+)$"),
    %% Sorted and deduplicated, so a failure prints every version rather than
    %% the first pair that happened to be compared.
    ?assertEqual([Image], lists:usort([Image, CiCheck, Tools, running_otp()])).

%% CI tests in the image that builds, and neither image can move under a tag.
%% The builder stage and lint name ONE image, so a green lint is a statement
%% about the toolchain the release is built with; both FROM lines carry a
%% digest, so a re-pushed tag cannot change what builds or what runs.
ci_builds_in_the_builder_and_both_images_are_digest_pinned_test() ->
    Digest = "@sha256:[0-9a-f]{64}",
    Builder = pinned("Containerfile", "^FROM (\\S+" ++ Digest ++ ") AS builder$"),
    ?assertMatch(<<_/binary>>, pinned("Containerfile", "^FROM (\\S+" ++ Digest ++ ")$")),
    ?assertEqual(Builder, pinned(".github/workflows/lint.yml", "^\\s+image: (\\S+)$")).

%% The full release, 28.4.3 and not 28: `otp_release' names only the major.
running_otp() ->
    {ok, Version} = file:read_file(filename:join([code:root_dir(), "releases",
                                                  erlang:system_info(otp_release),
                                                  "OTP_VERSION"])),
    string:trim(Version).

pinned(Relative, Pattern) ->
    {ok, Text} = file:read_file(alongside(Relative)),
    {match, [Version]} = re:run(Text, Pattern,
                                [multiline, {capture, all_but_first, binary}]),
    Version.

%% Relative to the beam rather than the working directory, because eunit runs
%% from wherever the developer happens to be standing.
alongside(Name) -> climb(filename:dirname(code:which(?MODULE)), Name, 8).

climb(_Dir, Name, 0) -> Name;
climb(Dir, Name, Left) ->
    Candidate = filename:join(Dir, Name),
    found(filelib:is_regular(Candidate), Candidate, Dir, Name, Left).

found(true, Candidate, _Dir, _Name, _Left) -> Candidate;
found(false, _Candidate, Dir, Name, Left) ->
    climb(filename:dirname(Dir), Name, Left - 1).

%% Each capability of its own requires a sealed call, and macula refuses
%% `required' without kem_advertise: a release that dropped the line would not
%% boot, so the baked config is parsed (every ${VAR} filled with a dummy) and
%% asserted.
kem_advertise_is_enabled_test() ->
    {ok, Text} = file:read_file(alongside("config/sys.config.src")),
    Substituted = re:replace(Text, <<"\\$\\{[A-Z_]+\\}">>, <<"0">>, [global, {return, list}]),
    {ok, Tokens, _} = erl_scan:string(Substituted),
    {ok, Config} = erl_parse:parse_term(Tokens),
    Macula = proplists:get_value(macula, Config),
    ?assertEqual(enabled, proplists:get_value(kem_advertise, Macula)).

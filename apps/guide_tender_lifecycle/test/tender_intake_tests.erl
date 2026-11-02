%%% @doc Today's intake (T12, T5): the cap, the drops, the day's roll.
-module(tender_intake_tests).

-include_lib("eunit/include/eunit.hrl").

intake_test_() ->
    {setup,
     fun() -> os:putenv("MCL_TENDERS_DAILY_CAP", "2"), {ok, Pid} = tender_intake:start_link(), unlink(Pid), Pid end,
     fun(Pid) -> stopped(Pid), os:unsetenv("MCL_TENDERS_DAILY_CAP") end,
     fun(_) ->
             [?_test(begin
                         %% Asking takes no place; a stored spot does.
                         ?assertEqual(ok, tender_intake:admit()),
                         ?assertEqual(ok, tender_intake:admit()),
                         ?assertMatch({ok, #{spotted := 0}}, tender_intake:today()),
                         ok = tender_intake:spotted(),
                         ?assertEqual(ok, tender_intake:admit()),
                         ok = tender_intake:spotted(),
                         ?assertEqual(capped, tender_intake:admit()),
                         ?assertEqual(capped, tender_intake:admit()),
                         ok = tender_intake:noted(),
                         {ok, T} = tender_intake:today(),
                         ?assertMatch(#{spotted := 2, dropped := 2, cap := 2,
                                        last_notice_at := At} when At > 0, T),
                         ?assertMatch({match, _}, re:run(maps:get(day, T), "^[0-9]{4}-[0-9]{2}-[0-9]{2}$"))
                     end)]
     end}.

a_new_day_starts_the_count_again_test() ->
    Yesterday = #{day => {2000, 1, 1}, spotted => 500, dropped => 7, cap => 500, last_notice_at => 1},
    {reply, ok, St} = tender_intake:handle_call(admit, self(), Yesterday),
    ?assertMatch(#{spotted := 0, dropped := 0, last_notice_at := 1}, St),
    {reply, ok, Spotted} = tender_intake:handle_call(spotted, self(), Yesterday),
    ?assertMatch(#{spotted := 1, dropped := 0}, Spotted),
    ?assertNotEqual({2000, 1, 1}, maps:get(day, St)).

the_cap_is_a_positive_integer_or_500_test() ->
    [begin
         os:putenv("MCL_TENDERS_DAILY_CAP", V),
         ?assertEqual(Want, tender_intake:cap())
     end || {V, Want} <- [{"10", 10}, {"0", 500}, {"-3", 500}, {"ten", 500}, {"10x", 500}]],
    os:unsetenv("MCL_TENDERS_DAILY_CAP"),
    ?assertEqual(500, tender_intake:cap()).

a_dead_counter_admits_nothing_test() ->
    ?assertEqual(undefined, whereis(tender_intake)),
    ?assertEqual(capped, tender_intake:admit()),
    ?assertEqual({error, unavailable}, tender_intake:today()).

%% Waits for the process to be gone, so the next start of its name cannot race it.
stopped(Pid) ->
    Ref = monitor(process, Pid),
    exit(Pid, shutdown),
    receive {'DOWN', Ref, process, Pid, _} -> ok after 5000 -> error({still_alive, Pid}) end.

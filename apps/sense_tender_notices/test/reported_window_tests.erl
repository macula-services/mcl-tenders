%%% @doc The publication numbers already reported: bounded, newest kept,
%%% each once. It is disposable and rebuilt empty on restart, which can report
%%% a day again; that is harmless, because company nodes deduplicate by
%%% publication number.
-module(reported_window_tests).

-include_lib("eunit/include/eunit.hrl").

ids(N) -> [integer_to_binary(I) || I <- lists:seq(1, N)].

an_empty_window_has_seen_nothing_test() ->
    W = reported_window:new(10),
    ?assertNot(reported_window:seen(<<"1-2026">>, W)),
    ?assertEqual(0, reported_window:size(W)).

a_marked_number_is_seen_test() ->
    W = reported_window:mark(<<"1-2026">>, reported_window:new(10)),
    ?assert(reported_window:seen(<<"1-2026">>, W)).

each_number_is_held_once_test() ->
    W = lists:foldl(fun reported_window:mark/2, reported_window:new(10), [<<"a">>, <<"a">>, <<"a">>]),
    ?assertEqual(1, reported_window:size(W)).

%% The oldest leave once the window is full, so memory stays bounded however
%% many notices TED publishes.
the_window_keeps_the_newest_test() ->
    W = lists:foldl(fun reported_window:mark/2, reported_window:new(3), ids(5)),
    ?assertEqual(3, reported_window:size(W)),
    ?assertEqual([false, false, true, true, true],
                 [reported_window:seen(I, W) || I <- ids(5)]).

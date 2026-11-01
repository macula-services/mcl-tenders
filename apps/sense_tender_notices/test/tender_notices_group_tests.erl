%%% @doc The realm's tenders group: what a sealed publish hands macula, and
%%% that nothing goes out, or is even attempted, in the clear.
-module(tender_notices_group_tests).

-include_lib("eunit/include/eunit.hrl").

-define(TOKEN, "canary-group-ucan-7f3a").
-define(ORG_KEY, "aa00000000000000000000000000000000000000000000000000000000000000").

with_env(Vars, Test) ->
    Old = [{K, os:getenv(K)} || {K, _} <- Vars],
    [os:putenv(K, V) || {K, V} <- Vars],
    try Test() after [restore(K, V) || {K, V} <- Old] end.

restore(K, false) -> os:unsetenv(K);
restore(K, V) -> os:putenv(K, V).

set_up(Test) -> with_env([{"MCL_TENDERS_GROUP_UCAN", ?TOKEN}, {"MCL_GROUP_ORG_KEY_ID", ?ORG_KEY}], Test).

unset(Test) -> with_env([{"MCL_TENDERS_GROUP_UCAN", ""}, {"MCL_GROUP_ORG_KEY_ID", ""}], Test).

%% The group is the org-owned prefix every fact topic of the realm lies under.
the_prefix_covers_the_fact_topic_test() ->
    Prefix = tender_notices_group:prefix(<<"io.macula">>),
    ?assertEqual(<<"io.macula/mcl-tenders/tenders">>, Prefix),
    Topic = mcl_tenders_facts:topic(<<"io.macula">>),
    ?assertEqual(<<Prefix/binary, "/">>, binary:part(Topic, 0, byte_size(Prefix) + 1)).

%% Fail closed: the setup names what it lacks, by variable and never by value.
the_missing_setup_is_named_test() ->
    unset(fun() -> ?assertEqual(["MCL_TENDERS_GROUP_UCAN", "MCL_GROUP_ORG_KEY_ID"],
                                tender_notices_group:missing()) end),
    set_up(fun() -> ?assertEqual([], tender_notices_group:missing()) end).

%% A short or non-hex org key id stops the boot naming the variable: it would
%% match nothing, and every pull would be refused while /health said ok.
a_malformed_org_key_id_is_refused_test() ->
    [with_env([{"MCL_GROUP_ORG_KEY_ID", Bad}],
              fun() -> ?assertError({mcl_tenders_group, {not_64_hex, "MCL_GROUP_ORG_KEY_ID"}},
                                    tender_notices_group:org_key_id()) end)
     || Bad <- ["abc", lists:duplicate(64, $z)]].

%% T3 (publisher side): the publish names the realm's group and carries the
%% admission token; one frame, no clear announcements.
the_publish_is_sealed_under_the_realm_group_test() ->
    set_up(fun() ->
        Self = self(),
        Publish = fun(Pool, Realm, Topic, Payload, Opts) ->
                          Self ! {published, Pool, Realm, Topic, Payload, Opts}, ok end,
        #{mode := sync, publisher_opts := #{announce := false, publish := P4}} =
            tender_notices_group:publish_opts(<<"io.macula">>, #{mode => sync}, Publish),
        ok = P4(pool, <<0:256>>, <<"io.macula/mcl-tenders/tenders/wire/x_v1">>, #{a => 1}),
        receive {published, pool, <<0:256>>, _, #{a := 1}, Opts} ->
            ?assertEqual(#{group => <<"io.macula/mcl-tenders/tenders">>,
                           ucan_token => list_to_binary(?TOKEN)}, Opts)
        after 0 -> ?assert(false)
        end
    end).

%% Without the token nothing is handed to macula: no clear publish is tried.
no_token_no_publish_test() ->
    unset(fun() ->
        Publish = fun(_, _, _, _, _) -> erlang:error(published_without_a_token) end,
        #{publisher_opts := #{publish := P4}} =
            tender_notices_group:publish_opts(<<"io.macula">>, #{}, Publish),
        ?assertEqual({error, {group, no_admission_token}}, P4(pool, <<0:256>>, <<"t">>, #{}))
    end).

%% The token is read at the publish and held nowhere a log or a crash report
%% could print: not in the options, not in the function's environment.
the_token_is_held_in_no_term_test() ->
    set_up(fun() ->
        Opts = tender_notices_group:publish_opts(<<"io.macula">>, #{mode => sync}),
        Printed = [term_to_binary(Opts), iolist_to_binary(io_lib:format("~p", [Opts]))],
        ?assertEqual([nomatch, nomatch], [binary:match(B, list_to_binary(?TOKEN)) || B <- Printed])
    end).

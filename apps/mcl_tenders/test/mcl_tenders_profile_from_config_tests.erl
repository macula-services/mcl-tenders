%%% @doc The deployment describes the realm's profile at boot
%%% (describe_tender_profile_from_config), on the released pipeline: a real
%%% store, evoq's router, the aggregate, the projection and the read model.
%%%
%%%   - unset: nothing is described;
%%%   - a bad CPV code or a country that is not alpha-3: refused with its
%%%     reason, nothing described;
%%%   - set, on a profile never described: described, by the node's own id;
%%%   - a later boot with other config: refused `already_described', the first
%%%     description kept;
%%%   - a profile the realm described over the mesh: kept the same way.
%%% Nothing here stops the boot: described/3 answers `ok' every time.
-module(mcl_tenders_profile_from_config_tests).

-include_lib("eunit/include/eunit.hrl").

-define(NODE, <<16#b7:256>>).
-define(MEMBER, <<16#a1:256>>).

profile_from_config_test_() ->
    {setup, fun() -> mcl_tenders_pipeline:start("mcl_tenders_profile_from_config_tests") end,
     fun mcl_tenders_pipeline:stop/1,
     {inorder, [fun nothing_is_described_when_unset/0,
                fun a_bad_code_is_refused_by_its_reason/0,
                fun an_undescribed_profile_is_described_by_the_node/0,
                fun a_described_profile_is_kept_on_the_next_boot/0,
                fun a_profile_described_over_the_mesh_is_kept/0]}}.

nothing_is_described_when_unset() ->
    ok = maybe_initiate_tender_profile:for_realm(realm()),
    mcl_tenders_pipeline:eventually(fun() -> cpv() end, []),
    ?assertEqual(off, describe_tender_profile_from_config:command(realm(), ?NODE, env(false, false))),
    ?assertEqual(ok, describe_tender_profile_from_config:described(realm(), ?NODE, env(false, false))),
    ?assertEqual(off, describe_tender_profile_from_config:command(realm(), ?NODE, env("", ""))).

a_bad_code_is_refused_by_its_reason() ->
    [?assertEqual({Cpv, Countries, Why},
                  {Cpv, Countries,
                   element(2, describe_tender_profile_from_config:command(realm(), ?NODE,
                                                                          env(Cpv, Countries)))})
     || {Cpv, Countries, Why} <- [{"7200000x", "BEL", invalid_cpv_codes},
                                  {"72000000,", "BEL", invalid_cpv_codes},
                                  {"72000000", "BE", invalid_countries},
                                  {"72000000", "bel", invalid_countries},
                                  {"72000000", false, profile_countries_unset},
                                  {false, "BEL", profile_cpv_unset}]],
    ?assertEqual({error, no_caller},
                 describe_tender_profile_from_config:command(realm(), undefined, env("72000000", "BEL"))),
    ?assertEqual(ok, describe_tender_profile_from_config:described(realm(), ?NODE, env("72000000", "BE"))),
    ?assertEqual([], cpv()).

an_undescribed_profile_is_described_by_the_node() ->
    ?assertEqual(ok, describe_tender_profile_from_config:described(realm(), ?NODE,
                                                                   env(" 72000000 ", "BEL"))),
    mcl_tenders_pipeline:eventually(fun() -> cpv() end, [<<"72000000">>]),
    {ok, P} = get_tender_profile:find(realm()),
    ?assertMatch(#{countries := [<<"BEL">>], keywords := [], exclusions := []}, P),
    ?assertEqual(binary:encode_hex(?NODE, lowercase), described_by(P)).

a_described_profile_is_kept_on_the_next_boot() ->
    {ok, Cmd} = describe_tender_profile_from_config:command(realm(), ?NODE, env("48000000", "NLD")),
    ?assertEqual({error, already_described}, maybe_describe_tender_profile:dispatch(Cmd)),
    ?assertEqual(ok, describe_tender_profile_from_config:described(realm(), ?NODE,
                                                                   env("48000000", "NLD"))),
    ?assertEqual([<<"72000000">>], cpv()).

a_profile_described_over_the_mesh_is_kept() ->
    {_, #{}} = mcl_tenders_pipeline:call(<<"describe_tender_profile">>,
                                         #{cpv_codes => [{text, <<"30000000">>}],
                                           countries => [{text, <<"FRA">>}]}, ?MEMBER),
    mcl_tenders_pipeline:eventually(fun() -> cpv() end, [<<"30000000">>]),
    {ok, Cmd} = describe_tender_profile_from_config:command(realm(), ?NODE, env("72000000", "BEL")),
    ?assertEqual({error, already_described}, maybe_describe_tender_profile:dispatch(Cmd)),
    ?assertEqual([<<"30000000">>], cpv()).

%%--------------------------------------------------------------------
%% Fixtures
%%--------------------------------------------------------------------

realm() -> mcl_tenders_pipeline:realm().

env(Cpv, Countries) ->
    fun("MCL_TENDERS_PROFILE_CPV") -> Cpv;
       ("MCL_TENDERS_PROFILE_COUNTRIES") -> Countries
    end.

cpv() -> cpv_of(get_tender_profile:find(realm())).

cpv_of({ok, #{cpv_codes := Cpv}}) -> Cpv;
cpv_of({error, Why}) -> Why.

%% The read model keeps a node id as hex, or as its 32 bytes.
described_by(#{described_by := <<_:256>> = By}) -> binary:encode_hex(By, lowercase);
described_by(#{described_by := By}) -> By.

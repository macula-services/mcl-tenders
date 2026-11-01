%%% @doc Every procedure's reply, as a client reads it off the wire.
%%%
%%% As in mcl-jobs (mcl-jobs#4), the reply keys of each procedure are pinned in
%%% ONE table, `replies/0', and three things are held to it:
%%%
%%%   - each responder's own handle_request/2, called with a payload shaped as
%%%     macula delivers it and run against a real store and read model, gives
%%%     those keys once its reply has been through macula's own CBOR encoding
%%%     and the strict decoder a caller uses;
%%%   - a refusal is `{reason}' and nothing else, for every procedure;
%%%   - the README's procedure table names the same keys, and lists the same
%%%     procedures as capabilities/0.
-module(mcl_tenders_wire_replies_tests).

-include_lib("eunit/include/eunit.hrl").

-define(MEMBER, <<16#a1:256>>).
-define(PROFILE, [<<"cpv_codes">>, <<"countries">>, <<"described_at">>, <<"described_by">>,
                  <<"description">>, <<"exclusions">>, <<"keywords">>]).

%% THE TABLE. Per procedure: the keys every success reply carries, and the keys
%% it may carry.
replies() ->
    [{<<"describe_tender_profile">>, {[], []}},
     {<<"get_tender_profile">>,      {?PROFILE, []}}].

the_table_names_every_announced_procedure_test() ->
    Announced = [maps:get(name, C) || C <- mcl_tenders_service:capabilities()],
    ?assertEqual(lists:sort(Announced), lists:sort(proplists:get_keys(replies()))).

the_readme_names_the_same_reply_keys_test() ->
    Expected = lists:sort([{Name, lists:sort(Required ++ [<<K/binary, "?">> || K <- Optional])}
                           || {Name, {Required, Optional}} <- replies()]),
    ?assertEqual(Expected, lists:sort(readme_replies())).

wire_replies_test_() ->
    {setup, fun() -> mcl_tenders_pipeline:start("mcl_tenders_wire_replies_tests") end,
     fun mcl_tenders_pipeline:stop/1,
     {timeout, 60, fun every_refusal_and_every_success_conforms/0}}.

every_refusal_and_every_success_conforms() ->
    %% Before the boot's initiation: nothing to describe, nothing to read.
    Refusals = [call(<<"describe_tender_profile">>, #{}, ?MEMBER),
                call(<<"get_tender_profile">>, #{}, ?MEMBER),
                call(<<"describe_tender_profile">>, #{countries => [{text, <<"be">>}]}, ?MEMBER)],
    [?assertMatch({_, [<<"reason">>], {text, _}},
                  {Name, maps:keys(Reply), maps:get(<<"reason">>, Reply)})
     || {Name, Reply} <- Refusals],
    ok = maybe_initiate_tender_profile:for_realm(mcl_tenders_pipeline:realm()),
    Described = call(<<"describe_tender_profile">>,
                     #{cpv_codes => [{text, <<"72000000">>}], countries => [{text, <<"BEL">>}]},
                     ?MEMBER),
    mcl_tenders_pipeline:eventually(
      fun() -> maps:get(<<"countries">>, element(2, call(<<"get_tender_profile">>, #{}, ?MEMBER)),
                        absent) end,
      [{text, <<"BEL">>}]),
    Successes = [Described, call(<<"get_tender_profile">>, #{}, ?MEMBER)],
    [?assertEqual({Name, conforms}, {Name, conforms(Name, Reply)}) || {Name, Reply} <- Successes],
    ?assertEqual(lists:sort(proplists:get_keys(replies())),
                 lists:usort([Name || {Name, _} <- Successes])),
    ?assertEqual(lists:sort(proplists:get_keys(replies())),
                 lists:usort([Name || {Name, _} <- Refusals])),
    %% Every value of the profile is text, a list of text or an integer:
    %% never bytes, never a boolean.
    {_, Profile} = lists:last(Successes),
    [?assert(texts(V) orelse is_integer(V)) || V <- maps:values(Profile)].

call(Name, Args, Caller) -> mcl_tenders_pipeline:call(Name, Args, Caller).

conforms(Name, Reply) ->
    {Required, Optional} = proplists:get_value(Name, replies()),
    conformed(lists:sort(maps:keys(Reply)) -- Optional =:= lists:sort(Required), Reply).

conformed(true, _Reply) -> conforms;
conformed(false, Reply) -> {wrong_keys, lists:sort(maps:keys(Reply))}.

texts({text, B}) when is_binary(B) -> true;
texts(List) when is_list(List) -> lists:all(fun texts/1, List);
texts(_) -> false.

%%--------------------------------------------------------------------
%% The README's procedure table
%%--------------------------------------------------------------------

%% Each `| `mcl-tenders/<name>` | payload | `{...}`...' row, as {Name, Keys}:
%% the first code span of the answer column, its keys with any `"' dropped
%% and a trailing `?' kept for an optional one.
readme_replies() ->
    {ok, Text} = file:read_file(alongside("README.md")),
    {match, Rows} = re:run(Text, "^\\| `mcl-tenders/([a-z_]+)` \\|[^|]*\\| `(\\{[^`]*\\})`",
                           [multiline, global, {capture, all_but_first, binary}]),
    [{Name, lists:sort(answer_keys(Answer))} || [Name, Answer] <- Rows].

answer_keys(Answer) ->
    Inner = binary:part(Answer, 1, byte_size(Answer) - 2),
    Flat = re:replace(Inner, "\\[[^]]*\\]", "", [global, {return, binary}]),
    [K || Part <- binary:split(Flat, <<",">>, [global]),
          K <- [answer_key(Part)], K =/= <<>>].

answer_key(Part) ->
    [Key | _] = binary:split(Part, <<":">>),
    binary:replace(string:trim(Key), <<"\"">>, <<>>, [global]).

alongside(Name) -> climb(filename:dirname(code:which(?MODULE)), Name, 8).

climb(_Dir, Name, 0) -> Name;
climb(Dir, Name, Left) ->
    Candidate = filename:join(Dir, Name),
    found(filelib:is_regular(Candidate), Candidate, Dir, Name, Left).

found(true, Candidate, _Dir, _Name, _Left) -> Candidate;
found(false, _Candidate, Dir, Name, Left) ->
    climb(filename:dirname(Dir), Name, Left - 1).

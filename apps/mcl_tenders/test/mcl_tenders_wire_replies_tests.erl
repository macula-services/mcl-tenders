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
-define(TENDER, <<"85e562c1-17d1-4192-a543-082edb9b62ab">>).
-define(DECLINED, <<"wire-declined-1">>).
-define(DISMISSED, <<"wire-dismissed-1">>).
-define(PROFILE, [<<"cpv_codes">>, <<"countries">>, <<"described_at">>, <<"described_by">>,
                  <<"description">>, <<"exclusions">>, <<"keywords">>]).
-define(DOSSIER, [<<"tender_id">>, <<"publication_number">>, <<"procedure_id">>, <<"notice_type">>,
                  <<"buyer_name">>, <<"buyer_country">>, <<"cpv_codes">>, <<"titles">>,
                  <<"description">>, <<"description_lang">>, <<"deadline_at">>,
                  <<"estimated_value">>, <<"currency">>, <<"published_at">>, <<"status">>,
                  <<"matched_cpv_codes">>, <<"matched_keywords">>, <<"spotted_at">>,
                  <<"corrected_by">>, <<"amended_at">>, <<"award_publication_number">>,
                  <<"award_published_at">>, <<"dismissed_by">>, <<"dismissed_at">>,
                  <<"pursued_by">>, <<"pursued_at">>, <<"declined_by">>, <<"declined_at">>,
                  <<"submitted_by">>, <<"submitted_at">>, <<"outcome">>, <<"outcome_by">>,
                  <<"outcome_at">>, <<"ted_url">>]).

%% THE TABLE. Per procedure: the keys every success reply carries, and the keys
%% it may carry.
replies() ->
    [{<<"describe_tender_profile">>, {[], []}},
     {<<"get_tender_profile">>,      {?PROFILE, []}},
     {<<"archive_tender_profile">>,  {[], []}},
     {<<"get_tenders_page">>,        {[<<"tenders">>, <<"text">>], []}},
     {<<"get_tender_by_id">>,        {?DOSSIER, []}},
     {<<"dismiss_tender">>,          {[], []}},
     {<<"pursue_tender">>,           {[], []}},
     {<<"decline_tender">>,          {[], []}},
     {<<"submit_tender_bid">>,       {[], []}},
     {<<"record_tender_outcome">>,   {[], []}},
     {<<"attach_tender_document">>,  {[], []}},
     {<<"record_tender_question">>,  {[], []}},
     {<<"get_tender_pursuit">>,      {[<<"documents">>, <<"questions">>], []}}].

%% One entry of the morning list, and the whole dossier.
summary_keys() ->
    lists:sort([<<"tender_id">>, <<"publication_number">>, <<"notice_type">>, <<"buyer_name">>,
                <<"buyer_country">>, <<"titles">>, <<"deadline_at">>, <<"estimated_value">>,
                <<"currency">>, <<"published_at">>, <<"status">>, <<"matched_cpv_codes">>,
                <<"matched_keywords">>, <<"ted_url">>]).

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
                call(<<"describe_tender_profile">>, #{countries => [{text, <<"be">>}]}, ?MEMBER),
                call(<<"get_tenders_page">>, #{limit => 0}, ?MEMBER),
                call(<<"get_tender_by_id">>, #{tender_id => {text, ?TENDER}}, ?MEMBER),
                call(<<"dismiss_tender">>, #{tender_id => {text, ?TENDER}}, ?MEMBER),
                call(<<"pursue_tender">>, #{tender_id => {text, ?TENDER}}, ?MEMBER),
                call(<<"decline_tender">>, #{tender_id => {text, ?TENDER}}, ?MEMBER),
                call(<<"submit_tender_bid">>, #{tender_id => {text, ?TENDER}}, ?MEMBER),
                call(<<"record_tender_outcome">>, #{tender_id => {text, ?TENDER},
                                                   outcome => {text, <<"won">>}}, ?MEMBER),
                call(<<"attach_tender_document">>, document(), ?MEMBER),
                call(<<"record_tender_question">>, question(), ?MEMBER),
                call(<<"get_tender_pursuit">>, #{tender_id => {text, ?TENDER}}, ?MEMBER),
                call(<<"archive_tender_profile">>, #{}, ?MEMBER)],
    [?assertMatch({_, [<<"reason">>], {text, _}},
                  {Name, maps:keys(Reply), maps:get(<<"reason">>, Reply)})
     || {Name, Reply} <- Refusals],
    ok = maybe_initiate_tender_profile:for_realm(mcl_tenders_pipeline:realm()),
    Described = call(<<"describe_tender_profile">>,
                     #{cpv_codes => [{text, <<"72000000">>}],
                       countries => [{text, <<"BEL">>}, {text, <<"NLD">>}]},
                     ?MEMBER),
    mcl_tenders_pipeline:eventually(
      fun() -> maps:get(<<"countries">>, element(2, call(<<"get_tender_profile">>, #{}, ?MEMBER)),
                        absent) end,
      [{text, <<"BEL">>}, {text, <<"NLD">>}]),
    {spot_tender, ok} = mcl_tenders_pipeline:reported(tender_notice_fixture:fact()),
    mcl_tenders_pipeline:eventually(
      fun() -> maps:is_key(<<"reason">>, element(2, call(<<"get_tender_by_id">>,
                                                         #{tender_id => {text, ?TENDER}}, ?MEMBER)))
      end, false),
    {_, Page} = Listed = call(<<"get_tenders_page">>, #{since => 0, limit => 10}, ?MEMBER),
    [Entry] = maps:get(<<"tenders">>, Page),
    ?assertEqual(summary_keys(), lists:sort(maps:keys(Entry))),
    %% Two more tenders: one the bid team declines, one it dismisses, since a
    %% pursued tender is no longer dismissed and a submitted one not declined.
    [{spot_tender, ok} = mcl_tenders_pipeline:reported(tender_notice_fixture:fact(#{procedure_id => Id}))
     || Id <- [?DECLINED, ?DISMISSED]],
    Successes = [Described, call(<<"get_tender_profile">>, #{}, ?MEMBER), Listed,
                 call(<<"get_tender_by_id">>, #{tender_id => {text, ?TENDER}}, ?MEMBER),
                 call(<<"dismiss_tender">>, #{tender_id => {text, ?DISMISSED}}, ?MEMBER),
                 call(<<"pursue_tender">>, #{tender_id => {text, ?TENDER}}, ?MEMBER),
                 call(<<"submit_tender_bid">>, #{tender_id => {text, ?TENDER}}, ?MEMBER),
                 call(<<"record_tender_outcome">>, #{tender_id => {text, ?TENDER},
                                                    outcome => {text, <<"lost">>}}, ?MEMBER),
                 call(<<"attach_tender_document">>, document(), ?MEMBER),
                 call(<<"record_tender_question">>, question(), ?MEMBER),
                 pursuit_with_papers(),
                 call(<<"pursue_tender">>, #{tender_id => {text, ?DECLINED}}, ?MEMBER),
                 call(<<"decline_tender">>, #{tender_id => {text, ?DECLINED}}, ?MEMBER),
                 %% Last, because archived is terminal.
                 call(<<"archive_tender_profile">>, #{}, ?MEMBER)],
    [?assertEqual({Name, conforms}, {Name, conforms(Name, Reply)}) || {Name, Reply} <- Successes],
    ?assertEqual(lists:sort(proplists:get_keys(replies())),
                 lists:usort([Name || {Name, _} <- Successes])),
    ?assertEqual(lists:sort(proplists:get_keys(replies())),
                 lists:usort([Name || {Name, _} <- Refusals])),
    %% Every value of the profile is text, a list of text or an integer:
    %% never bytes, never a boolean.
    {_, Profile} = lists:nth(2, Successes),
    [?assert(texts(V) orelse is_integer(V)) || V <- maps:values(Profile)],
    %% So is every value of a dossier and of a list entry, titles aside:
    %% a list of `{lang, title}', a language never a map key.
    {_, Dossier} = lists:nth(4, Successes),
    [?assert(texts(V) orelse is_integer(V)) || V <- maps:values(maps:remove(<<"titles">>, Dossier))],
    [?assertEqual([<<"lang">>, <<"title">>], lists:sort(maps:keys(T))) || T <- maps:get(<<"titles">>, Dossier)],
    %% The pursuit's papers: a list of documents and a list of questions, each
    %% a map of text and integers.
    {_, #{<<"documents">> := [Doc], <<"questions">> := [Q]}} = lists:nth(11, Successes),
    ?assertEqual([<<"attached_at">>, <<"attached_by">>, <<"location">>, <<"name">>, <<"sha256">>],
                 lists:sort(maps:keys(Doc))),
    ?assertEqual([<<"question">>, <<"question_id">>, <<"recorded_at">>, <<"recorded_by">>],
                 lists:sort(maps:keys(Q))),
    [?assert(texts(V) orelse is_integer(V)) || V <- maps:values(Doc) ++ maps:values(Q)].

document() ->
    #{tender_id => {text, ?TENDER}, name => {text, <<"offer.pdf">>},
      sha256 => {text, binary:copy(<<"ab">>, 32)}, location => {text, <<"bids/offer.pdf">>}}.

question() ->
    #{tender_id => {text, ?TENDER}, question => {text, <<"Is a hosted service allowed?">>}}.

%% Once the projections caught up, so the reply carries one of each.
pursuit_with_papers() ->
    Read = fun() -> call(<<"get_tender_pursuit">>, #{tender_id => {text, ?TENDER}}, ?MEMBER) end,
    mcl_tenders_pipeline:eventually(
      fun() -> {_, R} = Read(), {length(maps:get(<<"documents">>, R, [])),
                                 length(maps:get(<<"questions">>, R, []))} end, {1, 1}),
    Read().

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

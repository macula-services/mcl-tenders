%%% @doc A `tender_notice_reported_v1' fact as the PM receives it, and the
%%% profile it is matched against. Synthetic values: this repository is public.
-module(tender_notice_fixture).

-export([fact/0, fact/1, notice/0, notice/1, profile/0, profile/1, realm/0, member/0]).

realm() -> <<16#5e:256>>.
member() -> <<16#a1:256>>.

%% Keys and strings as the strict CBOR decode hands them over: {text, _}.
fact() ->
    #{{text, <<"publication_number">>} => {text, <<"745687-2026">>},
      {text, <<"procedure_id">>} => {text, <<"85e562c1-17d1-4192-a543-082edb9b62ab">>},
      {text, <<"notice_type">>} => {text, <<"contract_notice">>},
      {text, <<"buyer_name">>} => {text, <<"Gemeente Voorbeeld">>},
      {text, <<"buyer_country">>} => {text, <<"NLD">>},
      {text, <<"cpv_codes">>} => [{text, <<"72260000">>}, {text, <<"48000000">>}],
      {text, <<"titles">>} => #{{text, <<"nld">>} => {text, <<"Applicatie voor openbare orde">>},
                                {text, <<"eng">>} => {text, <<"Application for public order">>}},
      {text, <<"description">>} => {text, <<"De gemeente zoekt een Erlang-applicatie.">>},
      {text, <<"description_lang">>} => {text, <<"nld">>},
      {text, <<"deadline_at">>} => 1795000000000,
      {text, <<"estimated_value">>} => {text, <<"1257827.41">>},
      {text, <<"currency">>} => {text, <<"EUR">>},
      {text, <<"published_at">>} => 1793000000000,
      {text, <<"source">>} => {text, <<"ted">>}}.

%% Overrides by plain field name, wrapped as the wire wraps them.
fact(Overrides) ->
    maps:fold(fun(K, V, F) -> F#{{text, atom_to_binary(K)} => wrapped(V)} end, fact(), Overrides).

wrapped(B) when is_binary(B) -> {text, B};
wrapped(L) when is_list(L) -> [wrapped(V) || V <- L];
wrapped(M) when is_map(M) -> maps:from_list([{wrapped(K), wrapped(V)} || {K, V} <- maps:to_list(M)]);
wrapped(Other) -> Other.

notice() ->
    {ok, N} = tender_notice:from_fact(fact()),
    N.

notice(Overrides) ->
    {ok, N} = tender_notice:from_fact(fact(Overrides)),
    N.

profile() ->
    #{cpv_codes => [<<"72000000">>], countries => [<<"BEL">>, <<"NLD">>], keywords => [],
      exclusions => [], description => <<>>, described_by => <<>>, described_at => 0}.

profile(Overrides) -> maps:merge(profile(), Overrides).

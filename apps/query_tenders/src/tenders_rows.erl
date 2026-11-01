%% @doc How the query desks read the tenders table's cells back: a code list
%% from its newline-separated column, the titles from their JSON object, and
%% the notice's TED page rebuilt from its publication number.
-module(tenders_rows).

-export([listed/1, titles/1, ted_url/1]).

-define(PUBLICATION_NUMBER, "^[0-9]{1,8}-[0-9]{4}\\z").

%% @doc A newline-separated column as its list.
-spec listed(binary()) -> [binary()].
listed(<<>>) -> [];
listed(Lines) -> binary:split(Lines, <<"\n">>, [global]).

%% @doc The titles column as a list of `#{lang, title}', by language: on the
%% wire a language is a value, never a map key.
-spec titles(binary()) -> [#{lang := binary(), title := binary()}].
titles(Json) ->
    [#{lang => L, title => T} || {L, T} <- lists:sort(maps:to_list(json:decode(Json)))].

%% @doc The notice's page on TED, rebuilt from its publication number alone,
%% so no link from a payload is ever shown (T4). Empty for a number not in
%% TED's form, which the dossier never stores.
-spec ted_url(binary()) -> binary().
ted_url(Number) ->
    url(re:run(Number, ?PUBLICATION_NUMBER, [{capture, none}]), Number).

url(match, Number) -> <<"https://ted.europa.eu/en/notice/-/detail/", Number/binary>>;
url(nomatch, _Number) -> <<>>.

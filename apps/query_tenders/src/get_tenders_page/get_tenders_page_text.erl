%% @doc The morning list as a person reads it: one line per tender, best
%% first, with its title, buyer, country, deadline and TED notice id.
%%
%% An agent that asks "any tenders today?" over the mesh answers with this
%% text as it stands, so it carries nothing the summary does not: no link
%% (the publication number rebuilds it), no profile term. A notice's text is
%% a buyer's words, already bounded and stripped of control characters at
%% intake; a line break left in a title or a name is folded to a space here,
%% so one tender stays one line.
-module(get_tenders_page_text).

-export([rendered/1]).

%% TED's language code for English, the title shown when the notice has one.
-define(ENGLISH, <<"ENG">>).

%% @doc The page's summaries as text.
-spec rendered([map()]) -> binary().
rendered([]) ->
    <<"No tenders on the list.">>;
rendered(Summaries) ->
    Lines = [line(N, S) || {N, S} <- lists:enumerate(Summaries)],
    iolist_to_binary([counted(length(Summaries)), " (best first):\n",
                      lists:join("\n", Lines)]).

counted(1) -> <<"1 tender">>;
counted(N) -> [integer_to_binary(N), " tenders"].

line(N, #{titles := Titles, buyer_name := Buyer, buyer_country := Country,
          deadline_at := Deadline, publication_number := Number}) ->
    [integer_to_binary(N), ". ", one_line(title(Titles)),
     " | buyer: ", one_line(or_unknown(Buyer)), " (", or_unknown(Country), ")",
     " | deadline: ", deadline(Deadline),
     " | notice: ", Number].

%% English when the notice has it, else the first language it gives.
title(Titles) ->
    titled([T || #{lang := ?ENGLISH, title := T} <- Titles], Titles).

titled([English | _], _Titles) -> English;
titled([], [#{title := First} | _]) -> First;
titled([], []) -> <<"(no title)">>.

or_unknown(<<>>) -> <<"unknown">>;
or_unknown(Text) -> Text.

deadline(0) -> <<"none given">>;
deadline(Ms) -> list_to_binary(calendar:system_time_to_rfc3339(Ms, [{unit, millisecond}, {offset, "Z"}])).

one_line(Text) -> binary:replace(Text, [<<"\r\n">>, <<"\n">>, <<"\r">>], <<" ">>, [global]).

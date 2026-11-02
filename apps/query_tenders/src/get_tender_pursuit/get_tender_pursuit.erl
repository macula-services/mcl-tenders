%% @doc get_tender_pursuit: the bid team's papers on a spotted tender: the
%% pursuit's documents and the questions recorded on it (#25), oldest first.
%%
%% Its own desk, not part of get_tender_by_id, because the open reads switch
%% may open that one to every member of the realm, and these are the bid
%% team's: the procedure stays with the tenders role whatever the switch says.
-module(get_tender_pursuit).

-export([find/2, document_columns/0, question_columns/0]).

%% The longest tender id the dossier stores (tender_notice:valid_tender_id/1).
-define(MAX_ID_BYTES, 64).

%% @doc The columns of tender_documents this desk selects, in order; a test
%% pins them to tenders_read_model_store's schema.
-spec document_columns() -> [string()].
document_columns() ->
    ["name", "sha256", "location", "attached_by", "attached_at"].

%% @doc The columns of tender_questions this desk selects, in order; the same
%% test pins them.
-spec question_columns() -> [string()].
question_columns() ->
    ["question_id", "question", "recorded_by", "recorded_at"].

%% @doc The documents and questions of the spotted tender TenderId of Realm, a
%% 32-byte realm id. A spotted tender with none answers two empty lists.
-spec find(term(), term()) ->
          {ok, #{documents := [map()], questions := [map()]}}
        | {error, not_found | invalid_realm | invalid_tender_id | store_unavailable}.
find(<<_:256>> = Realm, TenderId)
  when is_binary(TenderId), byte_size(TenderId) > 0, byte_size(TenderId) =< ?MAX_ID_BYTES ->
    Key = [binary:encode_hex(Realm, lowercase), TenderId],
    spotted(tenders_query_store:q("SELECT 1 FROM tenders"
                                  " WHERE realm = ? AND tender_id = ? AND spotted_at IS NOT NULL",
                                  Key), Key);
find(<<_:256>>, _TenderId) ->
    {error, invalid_tender_id};
find(_Realm, _TenderId) ->
    {error, invalid_realm}.

spotted([_ | _], Key) -> papers(documents(Key), questions(Key));
spotted([], _Key) -> {error, not_found};
spotted({error, _}, _Key) -> {error, store_unavailable}.

documents(Key) ->
    tenders_query_store:q("SELECT " ++ lists:join(", ", document_columns()) ++ " FROM tender_documents"
                          " WHERE realm = ? AND tender_id = ? ORDER BY attached_at, sha256", Key).

questions(Key) ->
    tenders_query_store:q("SELECT " ++ lists:join(", ", question_columns()) ++ " FROM tender_questions"
                          " WHERE realm = ? AND tender_id = ? ORDER BY recorded_at, question_id", Key).

papers(Documents, Questions) when is_list(Documents), is_list(Questions) ->
    {ok, #{documents => [document(R) || R <- Documents],
           questions => [question(R) || R <- Questions]}};
papers(_Documents, _Questions) ->
    {error, store_unavailable}.

document([Name, Sha, Location, By, At]) ->
    #{name => Name, sha256 => Sha, location => Location, attached_by => By, attached_at => At}.

question([Id, Question, By, At]) ->
    #{question_id => Id, question => Question, recorded_by => By, recorded_at => At}.

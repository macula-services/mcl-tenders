%% @doc Supervises the QRY department: the read-only query store. The query
%% desks are pure modules answered by it.
-module(query_tenders_sup).

-behaviour(supervisor).

-export([start_link/0, init/1]).

start_link() -> supervisor:start_link({local, ?MODULE}, ?MODULE, []).

init([]) ->
    {ok, {#{strategy => one_for_one, intensity => 5, period => 10}, [
        #{id => tenders_query_store,
          start => {tenders_query_store, start_link, [project_tenders_sup:sqlite_path()]},
          restart => permanent, shutdown => 5000, type => worker,
          modules => [tenders_query_store]}
    ]}}.

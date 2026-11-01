%% @doc Supervises this service's own processes.
%%
%% NO CHILDREN OF ITS OWN: the desks run inside evoq's aggregate processes,
%% and the read side is supervised by project_tenders and query_tenders, each
%% its own application. An empty child list is the honest answer, not a
%% placeholder.
-module(mcl_tenders_sup).

-behaviour(supervisor).

-export([start_link/0, init/1]).

start_link() -> supervisor:start_link({local, ?MODULE}, ?MODULE, []).

init([]) ->
    {ok, {#{strategy => one_for_one, intensity => 5, period => 10}, []}}.

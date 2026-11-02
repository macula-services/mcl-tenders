%% @doc Supervises this service's own processes: the tenders group's
%% distributor, today's intake count of spotted tenders, then the TED sensor.
%%
%% The desks run inside evoq's aggregate processes, and the read side is
%% supervised by project_tenders and query_tenders, each its own application.
%% The distributor comes first, so the sensor's first sealed publish finds a
%% key to pull. Without the org key id it is `ignore' and holds no child, and
%% the sensor stays idle (tender_notices_group).
-module(mcl_tenders_sup).

-behaviour(supervisor).

-export([start_link/0, init/1]).

start_link() -> supervisor:start_link({local, ?MODULE}, ?MODULE, []).

init([]) ->
    {ok, {#{strategy => one_for_one, intensity => 5, period => 10},
          [#{id => mcl_tenders_group_keys,
             start => {mcl_tenders_group_keys, start_link, []},
             restart => permanent, shutdown => 5000, type => worker,
             modules => [mcl_tenders_group_keys]},
           #{id => tender_intake,
             start => {tender_intake, start_link, []},
             restart => permanent, shutdown => 5000, type => worker,
             modules => [tender_intake]},
           #{id => sense_ted_notices,
             start => {sense_ted_notices, start_link, []},
             restart => permanent, shutdown => 5000, type => worker,
             modules => [sense_ted_notices]}]}}.

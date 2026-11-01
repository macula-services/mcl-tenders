%% @doc Supervises the TED sensor, which owns its sweep, its reported window
%% and its publishing. One child.
-module(mcl_tenders_sensor_sup).

-behaviour(supervisor).

-export([start_link/0, init/1]).

start_link() -> supervisor:start_link({local, ?MODULE}, ?MODULE, []).

init([]) ->
    {ok, {#{strategy => one_for_one, intensity => 5, period => 10},
          [#{id => sense_ted_notices,
             start => {sense_ted_notices, start_link, []}}]}}.

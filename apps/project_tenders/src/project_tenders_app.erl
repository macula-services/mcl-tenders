%% @doc OTP application entry for the PRJ department.
%%
%% Starting this app opens the SQLite read model and registers the
%% projections with evoq. mcl_tenders lists this app among its own, so it
%% starts first, and by the time mcl_tenders_app opens the store subscription
%% and its catch-up replay runs, every projection is listening.
-module(project_tenders_app).

-behaviour(application).

-export([start/2, stop/1]).

start(_Type, _Args) -> project_tenders_sup:start_link().

stop(_State) -> ok.

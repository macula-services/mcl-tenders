%% @doc OTP application entry for the QRY department.
-module(query_tenders_app).

-behaviour(application).

-export([start/2, stop/1]).

start(_Type, _Args) -> query_tenders_sup:start_link().

stop(_State) -> ok.

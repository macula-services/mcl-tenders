%% @doc The mcl_om service contract: what this service is and may do.
%%
%% SIX CALLBACKS, ALL REQUIRED. mcl_om resolves them BY NAME at startup, on a
%% live node, so a service that forgets one dies with `undef' where nobody is
%% watching. The `-behaviour' attribute below is what turns that into a compile
%% error instead, and the generated test suite guards the attribute itself.
%%
%% A SENSOR, NOT A SERVER, and it must stay one. It sweeps TED's public notices
%% and reports each new one as a fact (mcl_tenders_facts). It offers NO
%% procedure: a company node that could ask it "tell me more about notice X"
%% would tell it which notices matched, and so what the company is after (T3 of
%% the design's threat model). Like mcl-news it publishes under its own verified
%% identity and asks the realm for no extra authority. It holds no store: its
%% only memory is a bounded window of publication numbers already reported,
%% rebuilt empty on restart.
-module(mcl_tenders_sensor_service).

-behaviour(mcl_om_service).

-export([info/0, start/1, stop/1, health/0, capabilities/0, identity_spec/0]).

info() ->
    #{name => <<"mcl-tenders-sensor">>,
      version => <<"0.1.0">>,
      description => <<"Public tender sensor: reads new TED notices and reports each as one mesh fact">>}.

%% The realm name the topic carries is checked against the realm the pool
%% publishes in before the sensor starts.
start(_Opts) ->
    ok = mcl_tenders_facts:check_realm_name(),
    mcl_tenders_sensor_sup:start_link().

stop(_State) -> ok.

%% Green once the sensor runs. TED being unreachable is not a health failure
%% (the sweep backs off and tries again), and neither is a dark mesh (notices
%% wait until it returns), both deliberately: a restart fixes neither.
health() -> ok.

%% Nothing, and on purpose (T3): see the module doc. A company node reads the
%% fact and never asks the sensor anything.
capabilities() -> [].

%% THE AUTHORITY THIS SERVICE ASKS THE REALM FOR, and deliberately nothing more.
%% Ask for exactly the topics you publish and subscribe to. Popped, an attacker
%% gains precisely this and no more, which is the whole point of listing it.
%%
%% The scope is claimed now because it is the namespace every later resource
%% hangs under, and a scope costs nothing while a rename costs every deployed
%% peer.
identity_spec() ->
    #{scope => <<"mcl-tenders-sensor">>,
      actions => [],
      resources => [],
      ttl_days => 30}.

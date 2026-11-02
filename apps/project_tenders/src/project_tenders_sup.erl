%% @doc Supervises the PRJ department: the SQLite read-model store first, then
%% one evoq_event_handler per projection desk.
-module(project_tenders_sup).

-behaviour(supervisor).

-export([start_link/0, init/1, projections/0, sqlite_path/0]).

start_link() -> supervisor:start_link({local, ?MODULE}, ?MODULE, []).

%% @doc Every projection desk, one per event it projects.
-spec projections() -> [module()].
projections() ->
    [tender_profile_initiated_v1_to_tender_profiles,
     tender_profile_described_v1_to_tender_profiles,
     tender_profile_archived_v1_to_tender_profiles,
     tender_spotted_v1_to_tenders,
     tender_amended_v1_to_tenders,
     tender_award_noted_v1_to_tenders,
     tender_dismissed_v1_to_tenders].

%% @doc Where the read model lives: beside the event store, under the same
%% MCL_DATA_DIR and the same default as mcl_tenders_service:event_store/0. A
%% test in mcl_tenders pins the two together.
-spec sqlite_path() -> string().
sqlite_path() ->
    filename:join(chosen(os:getenv("MCL_DATA_DIR")), "tenders.sqlite3").

init([]) ->
    Store = #{id => tenders_read_model_store,
              start => {tenders_read_model_store, start_link, [sqlite_path()]},
              restart => permanent, shutdown => 5000, type => worker,
              modules => [tenders_read_model_store]},
    {ok, {#{strategy => one_for_one, intensity => 5, period => 10},
          [Store | [projection(P) || P <- projections()]]}}.

projection(Module) ->
    #{id => Module,
      start => {evoq_event_handler, start_link, [Module, #{}]},
      restart => permanent, shutdown => 5000, type => worker,
      modules => [evoq_event_handler]}.

chosen(false) -> "/tmp/mcl_tenders";
chosen("") -> "/tmp/mcl_tenders";
chosen(Path) -> Path.

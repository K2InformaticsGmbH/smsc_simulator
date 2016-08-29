-module(smpp_simulator).
-include("logger.hrl").

-behaviour(application).
-behaviour(supervisor).

-export([start/0,stop/0,restart/0]). %% console
-export([start/2, stop/1]). % application
-export([init/1]). % supervisor

restart() -> stop(), start().
start() -> application:start(?MODULE).
stop() -> application:stop(?MODULE).

%% ===================================================================
%% Application callbacks
%% ===================================================================

start(_StartType, _StartArgs) ->
    supervisor:start_link({local, ?MODULE}, ?MODULE, []).

stop(_State) ->
    ok.

%% ===================================================================
%% Supervisor callbacks
%% ===================================================================
-define(DEFAULT_PORT, 7777).
init([]) ->
    Port = get_app_env(listen_port, ?DEFAULT_PORT),
    {ok, {#{strategy => one_for_one, intensity => 1, period => 5},
          [#{id => smpp_server,
             start => {smpp_server, start_link, [Port]},
             restart => permanent, shutdown => 1000, type => worker,
             modules => [smpp_server]}]}}.

get_app_env(Opt, Default) ->
    case application:get_env(smpp_simulator, Opt) of
        {ok, Val} -> Val;
        _ -> Default
    end.

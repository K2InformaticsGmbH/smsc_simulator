-module(smpp_simulator).
-include("logger.hrl").

-behaviour(application).
-behaviour(supervisor).

-export([start/0,stop/0,restart/0]). %% console
-export([start/2, stop/1]). % application
-export([start_child/0, init/1]). % supervisor

restart() -> stop(), start().
start() -> application:start(?MODULE).
stop() -> application:stop(?MODULE).

%% ===================================================================
%% Application callbacks
%% ===================================================================

start(_StartType, _StartArgs) ->
    case start_link() of
      {ok, _} -> start_child();
      Other -> {error, Other}
    end.

stop(_State) ->
    ok.

%% ===================================================================
%% Supervisor callbacks
%% ===================================================================
-define(DEFAULT_PORT, 7777).
-define(TCP_OPTIONS, [binary,
                      {packet, 0},
                      {active, once},
                      {reuseaddr, true}]).

start_link() ->
    supervisor:start_link({local, ?MODULE}, ?MODULE, []).

init([]) ->
    Port = get_app_env(listen_port, ?DEFAULT_PORT),
    ?SYS_INFO("Creating SMPP server instance on port ~p~n", [Port]),
    {ok, ListenSocket} = gen_tcp:listen(Port, ?TCP_OPTIONS),
    {ok, {{simple_one_for_one, 10, 60},
         [{smpp_server,
          {smpp_server, start_link, [ListenSocket]},
          temporary, 1000, worker, [smpp_server]}
         ]}}.

start_child() ->
    supervisor:start_child(?MODULE, []).

get_app_env(Opt, Default) ->
    case application:get_env(smpp_simulator, Opt) of
        {ok, Val} -> Val;
        _ -> Default
    end.

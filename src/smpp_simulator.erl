-module(smpp_simulator).
-include("logger.hrl").

-behaviour(application).
-behaviour(supervisor).

-export([start/0,stop/0,restart/0]). % console
-export([start/2, stop/1]). % application
-export([init/1]). % supervisor
-export([start_smsc/1,list_smscs/0,stop_smsc/1,list_sessions/1]). % smscs

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

start_smsc(Port) ->
    supervisor:start_child(?MODULE, [Port]).

list_smscs() ->
    [element(2,process_info(P,registered_name))
     || {_,P,_,_} <- supervisor:which_children(?MODULE)].

list_sessions(Port) ->
    {links,Links} = process_info(whereis(smpp_server:name(Port)), links),
    [element(2, process_info(L, registered_name))
     || L <- Links,
        is_pid(L),
        element(2, process_info(L, registered_name)) /= ?MODULE].

stop_smsc(Port) ->
    supervisor:terminate_child(?MODULE, whereis(smpp_server:name(Port))).

%% ===================================================================
%% Supervisor callbacks
%% ===================================================================
init([]) ->
    {ok, {#{strategy => simple_one_for_one, intensity => 1, period => 5},
          [#{id => smpp_server,
             start => {smpp_server, start_link, []},
             restart => permanent, shutdown => 1000, type => worker,
             modules => [smpp_server]}]}}.

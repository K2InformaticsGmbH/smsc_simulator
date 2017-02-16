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

-record(router, {src, dst, pid}).

start(_StartType, _StartArgs) ->
    Slave = 'smpp_smsc_db@127.0.0.1',
    case net_adm:ping(Slave) of
        pong -> lager:info("DB node ~p", [Slave]);
        pang ->
            {ok, Slave} =
            slave:start_link(
              "127.0.0.1", smpp_smsc_db,
              lists:concat(["-setcookie ", erlang:get_cookie()])),
            ok = rpc:call(Slave, mnesia, start, []),
            {ok, _} = rpc:call(Slave, mnesia, change_config, [extra_db_nodes, [node()]]),
            RamCopies = rpc:call(Slave, mnesia, table_info, [schema, ram_copies]),
            {atomic, ok} = rpc:call(
                             Slave, mnesia, create_table,
                             [router, [{ram_copies, RamCopies},
                                       {attributes, record_info(fields, router)}]]),
            lager:info("MASTER for DB node ~p", [Slave])
    end,
    ok = mnesia:start(),
    {ok, _} = rpc:call(Slave, mnesia, change_config, [extra_db_nodes, [node()]]),
    {atomic, ok} = mnesia:add_table_copy(router, node(), ram_copies),
    yes = mnesia:force_load_table(router),
    ok = mnesia:wait_for_tables([router], 1000),
    supervisor:start_link({local, ?MODULE}, ?MODULE, []).

stop(_State) ->
    stopped = mnesia:stop(),
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
    lager:info("table router copied to ~p", [mnesia:table_info(router, ram_copies)]),
    {ok, {#{strategy => simple_one_for_one, intensity => 1, period => 5},
          [#{id => smpp_server,
             start => {smpp_server, start_link, []},
             restart => permanent, shutdown => 1000, type => worker,
             modules => [smpp_server]}]}}.

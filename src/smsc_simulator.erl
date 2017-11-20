-module(smsc_simulator).
-include("logger.hrl").

-behaviour(application).
-behaviour(supervisor).

-export([start/0,stop/0,restart/0]). % console
-export([start/2, stop/1]). % application
-export([init/1]). % application
-export([list/0, list_sessions/1, all_routes/0, all_routes/1, add_route/2,
         add_route/3, route/1, del_route/1]). % smscs

restart() -> stop(), start().
start() -> application:ensure_all_started(?MODULE).
stop() -> application:stop(?MODULE).

%% ===================================================================
%% Application callbacks
%% ===================================================================

-record(router, {src, dst, pid}).
-define(SLAVE,
begin
    [_,_Ip] = string:tokens(atom_to_list(node()), "@"),
    list_to_atom("smsc_db@"++_Ip)
end).


start(Proto, Port) when Proto == smpp; Proto == ucp ->
    [_,IpStr] = string:tokens(atom_to_list(node()), "@"),
    {ok,Ip} = inet:getaddr(IpStr, inet),
    {ok,_} = ranch:start_listener(
                Port, 100, ranch_tcp,
                [{ip, Ip}, {port, Port}],
                smsc_server, [Proto]);
start(tpi, {Port, DsPort}) ->
    [_,IpStr] = string:tokens(atom_to_list(node()), "@"),
    {ok,Ip} = inet:getaddr(IpStr, inet),
    {ok,_} =
    cowboy:start_clear(
      Port, 100, [{ip, Ip}, {port, Port}],
      #{env =>
        #{dispatch =>
          cowboy_router:compile([{'_', [{"/", smsc_server, DsPort}]}])
         }});
start(tpi, BadArgs) ->
    lager:error("bad TPI start parameters ~p", [BadArgs]),
    error(badarg);
start(_StartType, _StartArgs) ->
    Type =
    case net_adm:ping(?SLAVE) of
        pong ->
            lager:info("starting peer for DB node ~p", [?SLAVE]),
            peer;
        pang ->
            [_,Ip] = string:tokens(atom_to_list(node()), "@"),
            SlaveNode = ?SLAVE,
            {ok, SlaveNode} =
            slave:start_link(Ip, smsc_db,
                             lists:concat(["-setcookie ", erlang:get_cookie()])),
            {ok, Ps} = init:get_argument(pa),
            Paths = lists:merge(Ps),
            ok = rpc:call(?SLAVE, code, add_pathsa, [Paths]),
            {ok, _} = rpc:call(?SLAVE, application, ensure_all_started, [lager]),
            ok = rpc:call(?SLAVE, mnesia, start, []),
            {ok, _} = rpc:call(?SLAVE, mnesia, change_config,
                               [extra_db_nodes, [node()]]),
            RamCopies = rpc:call(?SLAVE, mnesia, table_info,
                                 [schema, ram_copies]),
            {atomic, ok} = rpc:call(
                             ?SLAVE, mnesia, create_table,
                             [router,
                              [{ram_copies, RamCopies},
                               {attributes, record_info(fields, router)}]]),
            erlang:spawn_link(?SLAVE, fun fix_routes/0),
            %erlang:spawn_link(?SLAVE, fun() -> io:format("!!!! NODE ~p~n", [node()]) end),
            lager:info("starting MASTER for DB node ~p", [?SLAVE]),
            master
    end,
    ok = mnesia:start(),
    {ok, _} = rpc:call(?SLAVE, mnesia, change_config,
                       [extra_db_nodes, [node()]]),
    {atomic, ok} = mnesia:add_table_copy(router, node(), ram_copies),
    yes = mnesia:force_load_table(router),
    ok = mnesia:wait_for_tables([router], 1000),
    {ok, SupPid} = supervisor:start_link({local, ?MODULE}, ?MODULE, []),
    {ok, SupPid, Type}.

stop(master) ->
    lager:info("stopping DB master"),
    spawn(
      fun() ->
              stopped = mnesia:stop(),
              lager:info("stopped mnesia")
      end),
    slave:stop(?SLAVE),
    lager:info("stopped salve ~p", [?SLAVE]);
stop(peer) ->
    lager:info("stopping non DB master"),
    spawn(
      fun() ->
              stopped = mnesia:stop(),
              lager:info("stopped mnesia")
      end);
stop(Port) -> ranch:stop_listener(Port).

%% ===================================================================

fix_routes() ->
    mnesia:subscribe({table, router, detailed}),
    lager:info("subscribed to routing table chnages..."),
    fix_routes_events().

fix_routes_events() ->
    receive
        Event ->
            try fix_routes_events(Event) catch _:Error ->
                lager:error("fix_routes_events(~p)~n~n~p~n~n~p",
                            [Event, Error, erlang:get_stacktrace()])
            end,
            fix_routes_events()
    end.
fix_routes_events(
  {mnesia_table_event,
   {write, router, #router{src = {default, Dst}, dst = Dst, pid = Pids}, _, _}}) ->
    case [P || P <- Pids, is_alive_pid(P) == true] of
        Pids ->
            lager:info("updating for dst ~p with ~p", [Dst, Pids]),
            case mnesia:dirty_select(
                   router, [{#router{src = '$1', dst = Dst, _='_'},
                             [{'/=','$1',{{default, Dst}}}],
                             ['$1']}]) of
                [] -> lager:info("no source for dst ~p with ~p", [Dst, Pids]);
                Routes when length(Routes) > 0 ->
                    lists:foldl(
                      fun(Src, [Pid|Acc]) ->
                              ok = mnesia:dirty_write(#router{src = Src, dst = Dst,
                                                              pid = Pid}),
                              Acc++[Pid]
                      end, Pids, Routes),
                    lager:info("added ~p sources for dst ~p with ~p",
                               [Routes, Dst, Pids])
            end;
        NewPids ->
            ok = mnesia:dirty_write(#router{src = {default, Dst}, dst = Dst, pid = NewPids})
    end;
fix_routes_events({mnesia_table_event,
                   {write, router, #router{src = Src, dst = Dst,
                                           pid = undefined}, _, _}}) ->
    case mnesia:dirty_select(
           router, [{#router{src = {default, Dst}, dst = Dst, pid = '$1'},
                     [], ['$1']}]) of
        [] -> lager:info("no default route for ~p", [Dst]);
        Pids when length(Pids) > 0 ->
            case lists:usort(
                   lists:foldl(
                     fun(Pid, Acc) ->
                        [{length(mnesia:dirty_select(
                                   router, [{#router{dst = Dst, pid = Pid},
                                             [], ['$_']}])), Pid} | Acc]
                     end, [], lists:flatten(Pids))) of
                [{_,Pid}|_] ->
                    ok = mnesia:dirty_write(#router{src = Src, dst = Dst,
                                                    pid = Pid}),
                    lager:info("route ~p -> ~p : ~p", [Src, Dst, Pid]);
                [] -> lager:info("no default route for ~p,~p", [Src, Dst])
            end
    end;
fix_routes_events({mnesia_table_event,{write,router,_,_,_}}) ->
    lager:info("ignore table write");
fix_routes_events({mnesia_table_event,
                   {delete, router, What, Olds, _}}) ->
    lager:info("deleted ~p from ~p", [What, Olds]);
fix_routes_events({mnesia_table_event,{_,schema,_,_,_}}) ->
    lager:info("ignore table schema events").

list() -> ranch:info().

list_sessions(Port) -> ranch:procs(Port, connections).

all_routes() ->
    mnesia:dirty_select(router, [{#router{_ = '_'}, [], ['$_']}]).
all_routes(DstShortId) ->
    mnesia:dirty_select(router, [{#router{dst = DstShortId, _ = '_'}, [],
                                  ['$_']}]).

add_route([Src|_] = Srcs, Dst) when is_list(Src) ->
    [add_route(S, Dst, undefined) || S <- Srcs];
add_route(Src, Dst) when Src /= default ->
    add_route(Src, Dst, undefined).
add_route(default, Dst, Pid) when is_pid(Pid) ->
    add_route(
      {default, Dst}, Dst,
      case mnesia:dirty_select(
             router, [{#router{src = {default, Dst}, dst = Dst, pid = '$1'}, [],
                       ['$1']}]) of
          [Pids] when is_list(Pids) -> lists:usort([Pid | Pids]);
          _ -> [Pid]
      end);
add_route(Src, Dst, Pid) when Pid == undefined; is_pid(Pid); is_list(Pid) ->
    ok = mnesia:dirty_write(#router{src = Src, dst = Dst, pid = Pid}).

del_route([Src|_] = Srcs) when is_list(Src) ->
    [del_route(S) || S <- Srcs];
del_route(Src) ->
    ok = mnesia:dirty_delete(router, Src).

route(Src) ->
    case mnesia:dirty_select(
           router, [{#router{src = Src, pid = '$1', _ = '_'}, [], ['$1']}]) of
        [Pid] when is_pid(Pid) ->
            case is_alive_pid(Pid) of
                true -> Pid;
                _ -> no_forwarder
            end;
        _ -> no_route
    end.

is_alive_pid(Pid) when is_pid(Pid) ->
    rpc:call(node(Pid), erlang, is_process_alive, [Pid]).

%% ===================================================================
%% Supervisor callbacks
%% ===================================================================
init([]) ->
    {ok, {#{strategy => one_for_one, intensity => 10, period => 10}, []}}.

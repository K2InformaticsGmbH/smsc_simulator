-module(smpp_client).
-behavior(gen_server).

-include("logger.hrl").
-include("smpp_parser/smpp_globals.hrl").

-export([start/3, stop/1, bind/1, send/2, send/4]).

%% gen_server callbacks
-export([init/1, handle_call/3, handle_cast/2, handle_info/2, terminate/2,
         code_change/3]).

-record(state, {ip, port, sock, system_id, buffer}).

start(SystemId, Ip, Port) when is_list(SystemId) ->
    {ok, Socket} = gen_tcp:connect(Ip, Port,
                                   [binary, {packet, 0}, {active, false}]),
    case gen_server:start({global, SystemId}, ?MODULE,
                          [SystemId, Ip, Port, Socket], []) of
        {ok, Pid} ->
            case gen_tcp:controlling_process(Socket, Pid) of
                ok ->
                    Pid ! arm,
                    ?SYS_INFO("Client ~p started ~p~n", [SystemId, Pid]);
                Else ->
                    ?SYS_ERROR("~p socket transfer failed ~p~n", [SystemId, Else]),
                    catch gen_tcp:close(Socket),
                    exit(Pid, kill)
            end;
        Else ->
            catch gen_tcp:close(Socket),
            ?SYS_ERROR("~p failed to start ~p~n", [SystemId, Else])
    end.

stop({global, SystemId} = ServerRef) when is_list(SystemId) ->
    ok = gen_server:stop(ServerRef);
stop(SystemId)  when is_list(SystemId) ->
    stop({global, SystemId}).

bind({global, SystemId} = ServerRef) when is_list(SystemId) ->
    {ok, Bins} =
    smpp_operation:pack(
      {9,0,1,
       [{address_range,[]}, {addr_npi,0}, {addr_ton,0}, {interface_version,52},
        {system_type,[]}, {password,"abcd123"}, {system_id,SystemId}]}),
    ok = gen_server:cast(ServerRef, list_to_binary(Bins));
bind(SystemId) when is_list(SystemId) ->
    bind({global, SystemId}).

send(SystemId, Pdu) when is_list(Pdu), is_list(SystemId)  ->
    PduBin = list_to_binary([list_to_integer(I,16)
                             || I <- re:split(Pdu, " ", [{return, list}])]),
    {ok, ParsedPdu} = smpp_operation:unpack(PduBin),
    {Cmd, _, Seq, Body} = smpp:cmd(ParsedPdu),
    send({global, SystemId}, Cmd, Seq, Body).
send({global, SystemId} = ServerRef, Cmd, Seq, Body) when is_list(SystemId) ->
    {ok, Bins} = smpp_operation:pack(smpp:cmd({Cmd,0,Seq,Body})),
    ok = gen_server:cast(ServerRef, list_to_binary(Bins));
send(SystemId, Cmd, Seq, Body) when is_list(SystemId) ->
    send({global, SystemId}, Cmd, Seq, Body).

init([SystemId, Ip, Port, Socket]) ->
    ?SYS_INFO("Initializing SMPP client ~p~n", [SystemId]),
    process_flag(trap_exit, true),
    {ok, #state{sock = Socket, ip = Ip, port = Port, system_id = SystemId}}.

handle_call(Msg, From, State) ->
    ?SYS_WARN("Unknown call from (~p): ~p", [From, Msg]),
    {reply, {ok, Msg}, State}.

handle_cast({_CmdId, _Status, _SeqNum, _Body} = Resp, State) ->
    {ok, BinList} = smpp_operation:pack(Resp),
    RespBin = list_to_binary(BinList),
    handle_cast(RespBin, State);
handle_cast(Pdu, State) when is_binary(Pdu) ->
    {ok, Unpacked} = smpp_operation:unpack(Pdu),
    ?SYS_INFO("Sending SMPP: ~p", [smpp:cmd(Unpacked)]),
    ok = gen_tcp:send(State#state.sock, Pdu),
    ok = inet:setopts(State#state.sock, [{active, once}]),
    {noreply, State};
handle_cast(Request, State) ->
    ?SYS_WARN("Unknown cast: ~p", [Request]),
    {noreply, State}.

handle_info(arm, State) ->
    ok = inet:setopts(State#state.sock, [{active, once}]),
    {noreply, State};
handle_info({tcp, Sock, Data}, State = #state{buffer = B, sock = Sock}) ->
    {Messages, Incomplete} = smpp_server:try_decode(Data, B),
    ok = inet:setopts(Sock, [{active, once}]),
    [?SYS_INFO("RX : ~p~n", [smpp:cmd(Message)]) || Message <- Messages],
    {noreply, State#state{buffer = Incomplete}};
handle_info({tcp_closed, Socket}, State = #state{sock = Socket, ip = Ip, port = Port}) ->
    catch gen_tcp:close(State#state.sock),
    case gen_tcp:connect(Ip, Port, [binary, {packet, 0}, {active, once}]) of
        {ok, Sock} ->
            ?SYS_INFO("Socket reconnected!~n", []),
            {noreply, State#state{sock = Sock}};
        Else -> {stop, {reconnect_failed, Else}, State}
    end.

terminate(Reason, State) ->
    catch gen_tcp:close(State#state.sock),
    ?SYS_ERROR("[~p] terminating : ~p", [State#state.system_id, Reason]).

code_change(_OldVsn, State, _Extra) ->
    {ok, State}.

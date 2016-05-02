-module(smpp_client).
-behavior(gen_server).

-include("logger.hrl").
-include("smpp_parser/smpp_globals.hrl").

-export([start/3, stop/1, bind/1, send/4]).

%% gen_server callbacks
-export([init/1, handle_call/3, handle_cast/2, handle_info/2, terminate/2,
         code_change/3]).

-record(state, {ip, port, sock, system_id, buffer}).

start(SystemId, Ip, Port) ->
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

stop({global, _} = ServerRef) ->
    ok = gen_server:stop(ServerRef);
stop(SystemId) ->
    stop({global, SystemId}).

bind({global, SystemId} = ServerRef) ->
    {ok, Bins} =
    smpp_operation:pack(
      {9,0,1,
       [{address_range,[]}, {addr_npi,0}, {addr_ton,0}, {interface_version,52},
        {system_type,[]}, {password,"zuj_4115"}, {system_id,SystemId}]}),
    ok = gen_server:cast(ServerRef, list_to_binary(Bins));
bind(SystemId) ->
    bind({global, SystemId}).

send({global, _} = ServerRef, Cmd, Seq, Body) ->
    {ok, Bins} = smpp_operation:pack(cmd({Cmd,0,Seq,Body})),
    ok = gen_server:cast(ServerRef, list_to_binary(Bins));
send(SystemId, Cmd, Seq, Body) ->
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
    {ok, Reply} = smpp_operation:unpack(Pdu),
    ?SYS_INFO("Sending SMPP reply: ~p", [smpp_server:cmd(Reply)]),
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
    [?SYS_INFO("RX : ~p~n", [Message]) || Message <- Messages],
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

cmd({unbind,S,SN,B})                     -> {?COMMAND_ID_UNBIND,                      S,SN,B};
cmd({outbind,S,SN,B})                    -> {?COMMAND_ID_OUTBIND,                     S,SN,B};
cmd({data_sm,S,SN,B})                    -> {?COMMAND_ID_DATA_SM,                     S,SN,B};
cmd({query_sm,S,SN,B})                   -> {?COMMAND_ID_QUERY_SM,                    S,SN,B};
cmd({cancel_sm,S,SN,B})                  -> {?COMMAND_ID_CANCEL_SM,                   S,SN,B};
cmd({submit_sm,S,SN,B})                  -> {?COMMAND_ID_SUBMIT_SM,                   S,SN,B};
cmd({replace_sm,S,SN,B})                 -> {?COMMAND_ID_REPLACE_SM,                  S,SN,B};
cmd({deliver_sm,S,SN,B})                 -> {?COMMAND_ID_DELIVER_SM,                  S,SN,B};
cmd({submit_multi,S,SN,B})               -> {?COMMAND_ID_SUBMIT_MULTI,                S,SN,B};
cmd({broadcast_sm,S,SN,B})               -> {?COMMAND_ID_BROADCAST_SM,                S,SN,B};
cmd({enquire_link,S,SN,B})               -> {?COMMAND_ID_ENQUIRE_LINK,                S,SN,B};
cmd({generic_nack,S,SN,B})               -> {?COMMAND_ID_GENERIC_NACK,                S,SN,B};
cmd({bind_receiver,S,SN,B})              -> {?COMMAND_ID_BIND_RECEIVER,               S,SN,B};
cmd({bind_transceiver,S,SN,B})           -> {?COMMAND_ID_BIND_TRANSCEIVER,            S,SN,B};
cmd({bind_transmitter,S,SN,B})           -> {?COMMAND_ID_BIND_TRANSMITTER,            S,SN,B};
cmd({alert_notification,S,SN,B})         -> {?COMMAND_ID_ALERT_NOTIFICATION,          S,SN,B};
cmd({query_broadcast_sm,S,SN,B})         -> {?COMMAND_ID_QUERY_BROADCAST_SM,          S,SN,B};
cmd({cancel_broadcast_sm,S,SN,B})        -> {?COMMAND_ID_CANCEL_BROADCAST_SM,         S,SN,B};
                                                       
cmd({unbind_resp,S,SN,B})                -> {?COMMAND_ID_UNBIND_RESP,                 S,SN,B};
cmd({data_sm_resp,S,SN,B})               -> {?COMMAND_ID_DATA_SM_RESP,                S,SN,B};
cmd({query_sm_resp,S,SN,B})              -> {?COMMAND_ID_QUERY_SM_RESP,               S,SN,B};
cmd({submit_sm_resp,S,SN,B})             -> {?COMMAND_ID_SUBMIT_SM_RESP,              S,SN,B};
cmd({cancel_sm_resp,S,SN,B})             -> {?COMMAND_ID_CANCEL_SM_RESP,              S,SN,B};
cmd({replace_sm_resp,S,SN,B})            -> {?COMMAND_ID_REPLACE_SM_RESP,             S,SN,B};
cmd({deliver_sm_resp,S,SN,B})            -> {?COMMAND_ID_DELIVER_SM_RESP,             S,SN,B};
cmd({submit_multi_resp,S,SN,B})          -> {?COMMAND_ID_SUBMIT_MULTI_RESP,           S,SN,B};
cmd({broadcast_sm_resp,S,SN,B})          -> {?COMMAND_ID_BROADCAST_SM_RESP,           S,SN,B};
cmd({enquire_link_resp,S,SN,B})          -> {?COMMAND_ID_ENQUIRE_LINK_RESP,           S,SN,B};
cmd({bind_receiver_resp,S,SN,B})         -> {?COMMAND_ID_BIND_RECEIVER_RESP,          S,SN,B};
cmd({bind_transceiver_resp,S,SN,B})      -> {?COMMAND_ID_BIND_TRANSCEIVER_RESP,       S,SN,B};
cmd({bind_transmitter_resp,S,SN,B})      -> {?COMMAND_ID_BIND_TRANSMITTER_RESP,       S,SN,B};
cmd({query_broadcast_sm_resp,S,SN,B})    -> {?COMMAND_ID_QUERY_BROADCAST_SM_RESP,     S,SN,B};
cmd({cancel_broadcast_sm_resp,S,SN,B})   -> {?COMMAND_ID_CANCEL_BROADCAST_SM_RESP,    S,SN,B}.

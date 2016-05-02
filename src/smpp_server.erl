-module(smpp_server).

-include("logger.hrl").
-include("smpp_parser/smpp_globals.hrl").

-behaviour(gen_server).

%% gen_server callbacks
-export([init/1,
         handle_call/3,
         handle_cast/2,
         handle_info/2,
         terminate/2,
         code_change/3]).

%% API
-export([start_link/1,
         stop/1,
         send_message/5,
         try_decode/2, cmd/1]).

-record(state, {port,  % listening port
                lsock, % listening socket
                sock,  % socket
                trn,   % message number
                status,
                buffer % TCP buffer
            }).

%%%===================================================================
%%% API
%%%===================================================================

start_link(LSock) ->
    gen_server:start_link(?MODULE, [LSock], []).

stop(Server) ->
    gen_server:cast(Server, stop).

send_message(Server, Seq, Src, Dst, Msg)
  when is_integer(Seq), is_integer(Src), is_integer(Dst), is_list(Msg) ->
    case whereis(Server) of
        undefined -> ?SYS_ERROR("SMSC ~p is dead", [Server]);
        Pid ->
            {ok, Pdu} =
            smpp_operation:pack(
              {?COMMAND_ID_DELIVER_SM, 0, Seq,
               [{short_message,Msg},{sm_default_msg_id,0},{data_coding,0},
                {replace_if_present_flag,0},{registered_delivery,0},
                {validity_period,[]},{schedule_delivery_time,[]},
                {priority_flag,1},{protocol_id,0},{esm_class,0},
                {destination_addr,integer_to_list(Dst)},{dest_addr_npi,1},
                {dest_addr_ton,1},{source_addr, integer_to_list(Src)},
                {source_addr_npi,1},{source_addr_ton,1},{service_type,[]}]}),
            gen_server:cast(Pid, {send_message, list_to_binary(Pdu)})
    end.

%%%===================================================================
%%% gen_server callbacks
%%%===================================================================

init([LSock]) ->
    ?SYS_INFO("Initializing SMPP server~n", []),
    gen_server:cast(self(), accept),
    process_flag(trap_exit, true),
    {ok, #state{lsock = LSock, trn = 0}}.

handle_call(Msg, From, State) ->
    ?SYS_WARN("Unknown call from (~p): ~p", [From, Msg]),
    {reply, {ok, Msg}, State}.

handle_cast(accept, State = #state{lsock = S}) ->
    {ok, Sock} = gen_tcp:accept(S),
    smpp_simulator:start_child(),
    ?SYS_INFO("Accepting: ~p", [Sock]),
    {noreply, State#state{sock = Sock}};

handle_cast({send_message, Msg}, State = #state{sock = Sock}) ->
    case catch send(Sock, Msg) of
        ok -> ok;
        Error -> ?SYS_ERROR("Send failed: ~p~n~p", [Msg, Error])
    end,
    {noreply, State};

handle_cast(stop, State) ->
    {stop, normal, State}.

handle_info({tcp, Sock, Data}, State = #state{buffer = B, sock = Sock}) ->
    {Messages, Incomplete} = try_decode(Data, B),
    [handle_data(Sock, M) || M <- Messages],
    {noreply, State#state{buffer = Incomplete}};

handle_info({tcp_closed, Sock}, State = #state{sock = Sock}) ->
    ?SYS_WARN("Socket ~p closed.", [Sock]),
    {stop, normal, State};
handle_info({tcp_closed, Socket}, State) ->
    ?SYS_WARN("Unknown socket ~p closed.", [Socket]),
    {stop, normal, State};

handle_info(Any, State) ->
    ?SYS_INFO("Unhandled message: ~p", [Any]),
    {noreply, State}.

terminate(Reason, _State) ->
    case [P || P <- registered(), whereis(P) == self()] of
        [RegName] ->
            ?SYS_INFO("~p : ~p", [RegName, Reason]);
        _ ->
            ?SYS_INFO("~p", [Reason])
    end.

code_change(_OldVsn, State, _Extra) ->
    {ok, State}.

%%%===================================================================
%%% Internal functions
%%%===================================================================

try_decode(Data, undefined) when is_binary(Data) ->
    try_decode(Data, []);
try_decode(Data, B) when is_binary(Data), is_binary(B) ->
    try_decode(<<Data/binary, B/binary>>, []);
try_decode(<<>>, PDUs) when is_list(PDUs) -> {PDUs, <<>>};
try_decode(<<CmdLen:32, Rest/binary>> = Buffer, PDUs) when is_list(PDUs) ->
    Len = CmdLen - 4,
    case Rest of
        <<PduRest:Len/binary-unit:8, NextPdus/binary>> ->
            BinPdu = <<CmdLen:32, PduRest/binary>>,
            case catch smpp_operation:unpack(BinPdu) of
                {ok, Pdu} ->
                    try_decode(NextPdus, PDUs++[Pdu]);
                {error, CmdId, Status, SeqNum} ->
                    ?SYS_ERROR("Error: {CmdId, Status, SeqNum} ~p", [{CmdId, Status, SeqNum}]),
                    {PDUs, Buffer};
                {'EXIT', Reason} ->
                    ?SYS_ERROR("Error: ~p", [Reason]),
                    {PDUs, Buffer}
            end;
        _ -> {PDUs, Buffer}
    end.

handle_data(Socket, {C,_,_,B} = Pdu) ->
    case lists:member(C, [?COMMAND_ID_BIND_RECEIVER,
                          ?COMMAND_ID_BIND_TRANSCEIVER,
                          ?COMMAND_ID_BIND_TRANSMITTER]) of
        true ->
            RegName = list_to_atom(
                        lists:flatten([atom_to_list(?MODULE),"_",
                                       proplists:get_value(system_id,B)])),
            erlang:register(RegName, self()),
            ?SYS_INFO("SMSC : ~p", [RegName]);
        false -> ok
    end,
    ?SYS_INFO("Req : ~p", [cmd(Pdu)]),
    case handle_message(Pdu) of
        {reply, Resp} ->
            try
                {ok, BinList} = smpp_operation:pack(Resp),
                RespBin = list_to_binary(BinList),
                {ok, Reply} = smpp_operation:unpack(RespBin),
                ?SYS_INFO("Sending SMPP reply: ~p", [cmd(Reply)]),
                send(Socket, RespBin)
            catch
                _:Error ->
                    ?SYS_ERROR("Error: ~p:~p", [Error,erlang:get_stacktrace()])
            end;
        _ ->
            inet:setopts(Socket, [{active, once}])
    end.

handle_message({CmdId,Status,SeqNum,Body}) ->
    if CmdId band 16#80000000 == 0 ->
           {reply, {CmdId bor 16#80000000, Status, SeqNum, Body}};
       true -> ignore
    end;
handle_message(Pdu) ->
    {reply, Pdu}.

send(S, Msg) ->
    gen_tcp:send(S, Msg),
    inet:setopts(S, [{active, once}]).

cmd({?COMMAND_ID_UNBIND,                      S,SN,B})    -> {unbind,S,SN,B};
cmd({?COMMAND_ID_OUTBIND,                     S,SN,B})    -> {outbind,S,SN,B};
cmd({?COMMAND_ID_DATA_SM,                     S,SN,B})    -> {data_sm,S,SN,B};
cmd({?COMMAND_ID_QUERY_SM,                    S,SN,B})    -> {query_sm,S,SN,B};
cmd({?COMMAND_ID_CANCEL_SM,                   S,SN,B})    -> {cancel_sm,S,SN,B};
cmd({?COMMAND_ID_SUBMIT_SM,                   S,SN,B})    -> {submit_sm,S,SN,B};
cmd({?COMMAND_ID_REPLACE_SM,                  S,SN,B})    -> {replace_sm,S,SN,B};
cmd({?COMMAND_ID_DELIVER_SM,                  S,SN,B})    -> {deliver_sm,S,SN,B};
cmd({?COMMAND_ID_SUBMIT_MULTI,                S,SN,B})    -> {submit_multi,S,SN,B};
cmd({?COMMAND_ID_BROADCAST_SM,                S,SN,B})    -> {broadcast_sm,S,SN,B};
cmd({?COMMAND_ID_ENQUIRE_LINK,                S,SN,B})    -> {enquire_link,S,SN,B};
cmd({?COMMAND_ID_GENERIC_NACK,                S,SN,B})    -> {generic_nack,S,SN,B};
cmd({?COMMAND_ID_BIND_RECEIVER,               S,SN,B})    -> {bind_receiver,S,SN,B};
cmd({?COMMAND_ID_BIND_TRANSCEIVER,            S,SN,B})    -> {bind_transceiver,S,SN,B};
cmd({?COMMAND_ID_BIND_TRANSMITTER,            S,SN,B})    -> {bind_transmitter,S,SN,B};
cmd({?COMMAND_ID_ALERT_NOTIFICATION,          S,SN,B})    -> {alert_notification,S,SN,B};
cmd({?COMMAND_ID_QUERY_BROADCAST_SM,          S,SN,B})    -> {query_broadcast_sm,S,SN,B};
cmd({?COMMAND_ID_CANCEL_BROADCAST_SM,         S,SN,B})    -> {cancel_broadcast_sm,S,SN,B};

cmd({?COMMAND_ID_UNBIND_RESP,                 S,SN,B})    -> {unbind_resp,S,SN,B};
cmd({?COMMAND_ID_DATA_SM_RESP,                S,SN,B})    -> {data_sm_resp,S,SN,B};
cmd({?COMMAND_ID_QUERY_SM_RESP,               S,SN,B})    -> {query_sm_resp,S,SN,B};
cmd({?COMMAND_ID_SUBMIT_SM_RESP,              S,SN,B})    -> {submit_sm_resp,S,SN,B};
cmd({?COMMAND_ID_CANCEL_SM_RESP,              S,SN,B})    -> {cancel_sm_resp,S,SN,B};
cmd({?COMMAND_ID_REPLACE_SM_RESP,             S,SN,B})    -> {replace_sm_resp,S,SN,B};
cmd({?COMMAND_ID_DELIVER_SM_RESP,             S,SN,B})    -> {deliver_sm_resp,S,SN,B};
cmd({?COMMAND_ID_SUBMIT_MULTI_RESP,           S,SN,B})    -> {submit_multi_resp,S,SN,B};
cmd({?COMMAND_ID_BROADCAST_SM_RESP,           S,SN,B})    -> {broadcast_sm_resp,S,SN,B};
cmd({?COMMAND_ID_ENQUIRE_LINK_RESP,           S,SN,B})    -> {enquire_link_resp,S,SN,B};
cmd({?COMMAND_ID_BIND_RECEIVER_RESP,          S,SN,B})    -> {bind_receiver_resp,S,SN,B};
cmd({?COMMAND_ID_BIND_TRANSCEIVER_RESP,       S,SN,B})    -> {bind_transceiver_resp,S,SN,B};
cmd({?COMMAND_ID_BIND_TRANSMITTER_RESP,       S,SN,B})    -> {bind_transmitter_resp,S,SN,B};
cmd({?COMMAND_ID_QUERY_BROADCAST_SM_RESP,     S,SN,B})    -> {query_broadcast_sm_resp,S,SN,B};
cmd({?COMMAND_ID_CANCEL_BROADCAST_SM_RESP,    S,SN,B})    -> {cancel_broadcast_sm_resp,S,SN,B}.

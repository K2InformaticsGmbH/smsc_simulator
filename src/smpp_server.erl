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
-export([start_link/1, stop/1, send/2, send/4, try_decode/2,
         auto_resp/1, auto_resp/2]).

-record(state, {lsock, % listening socket
                sock,  % socket
                trn = 0,   % message number
                status,
                buffer, % TCP buffer
                auto_response = true
            }).

%%%===================================================================
%%% API
%%%===================================================================

start_link(Port) ->
    gen_server:start_link(?MODULE, [Port], []).

stop(Server) ->
    gen_server:cast(Server, stop).

send(SystemId, Pdu) when is_integer(SystemId) ->
    send(integer_to_list(SystemId), Pdu);
send(SystemId, Pdu) when is_list(Pdu), is_list(SystemId)  ->
    Pid = whereis(list_to_atom(
                    lists:flatten([atom_to_list(?MODULE),"_",SystemId]))),
    if is_pid(Pid) ->
           PduBin = list_to_binary([list_to_integer(I,16)
                                    || I <- re:split(Pdu, " ", [{return, list}])]),
           {ok, ParsedPdu} = smpp_operation:unpack(PduBin),
           {Cmd, _, Seq, Body} = smpp:cmd(ParsedPdu),
           send(Pid, Cmd, Seq, Body);
       true ->
           ?SYS_ERROR("SMSC ~s is dead", [SystemId])
    end.

send(SystemId, Cmd, Seq, Body) when is_integer(SystemId) ->
    send(integer_to_list(SystemId), Cmd, Seq, Body);
send(SystemId, Cmd, Seq, Body) when is_list(SystemId) ->
    Pid = whereis(list_to_atom(
                    lists:flatten([atom_to_list(?MODULE),"_",SystemId]))),
    if is_pid(Pid) -> send(Pid, Cmd, Seq, Body);
       true -> ?SYS_ERROR("SMSC ~s is dead", [SystemId])
    end;
send(ServerPid, Cmd, Seq, Body) when is_pid(ServerPid) ->
    {ok, Bins} = smpp_operation:pack(smpp:cmd({Cmd,0,Seq,Body})),
    ok = gen_server:cast(ServerPid, {send_message, list_to_binary(Bins)}).

auto_resp(SystemId) -> auto_resp(SystemId, undefined).
auto_resp(SystemId, Value) when is_integer(SystemId) ->
    auto_resp(integer_to_list(SystemId), Value);
auto_resp(SystemId, Value) when is_list(SystemId) andalso
                                (Value == true
                                 orelse Value == false
                                 orelse Value == undefined) ->
    Pid = whereis(list_to_atom(
                    lists:flatten([atom_to_list(?MODULE),"_",SystemId]))),
    if is_pid(Pid) ->
           gen_server:call(Pid, {auto_response, Value});
       true -> ?SYS_ERROR("SMSC ~s is dead", [SystemId])
    end.

%%%===================================================================
%%% gen_server callbacks
%%%===================================================================

init([Port]) when is_integer(Port) ->
    process_flag(trap_exit, true),
    {ok, LSock} = gen_tcp:listen(Port, [binary, {packet, 0}, {active, false}]),
    ?SYS_INFO("Listening on ~p : ~p", [Port, LSock]),
    gen_server:cast(self(), accept),
    {ok, #state{lsock = LSock}};
init([Sock]) ->
    process_flag(trap_exit, true),
    ?SYS_INFO("Accepted: ~p", [Sock]),
    {ok, #state{sock = Sock}}.

handle_call({auto_response, AutoResponse}, _From, State) ->
     case AutoResponse of
         undefined ->
             {reply, State#state.auto_response, State};
         AutoResponse ->
             {reply, {ok, AutoResponse}, State#state{auto_response = AutoResponse}}
     end;
handle_call(Msg, From, State) ->
    ?SYS_WARN("Unknown call from (~p): ~p", [From, Msg]),
    {reply, {ok, Msg}, State}.

handle_cast(accept, State = #state{lsock = LSock}) ->
    ?SYS_INFO("Accepting: ~p", [LSock]),
    {ok, Sock} = gen_tcp:accept(LSock),
    {ok,  Pid} = gen_server:start(?MODULE, [Sock], []),
    ok = gen_tcp:controlling_process(Sock, Pid),
    ok = gen_server:cast(Pid, arm),
    ok = gen_server:cast(self(), accept),
    {noreply, State};
handle_cast(arm, State = #state{sock = Sock}) ->
    ok = inet:setopts(Sock, [{active,once}]),
    {noreply, State};
handle_cast({send_message, Msg}, State = #state{sock = Sock}) ->
    case catch send_low(Sock, Msg) of
        ok -> ok;
        Error -> ?SYS_ERROR("Send failed: ~p~n~p", [Msg, Error])
    end,
    {noreply, State};

handle_cast(stop, State) ->
    {stop, normal, State}.

handle_info({tcp, Sock, Data}, State = #state{buffer = B, sock = Sock,
                                              auto_response = AutoResponse}) ->
    {Messages, Incomplete} = try_decode(Data, B),
    [handle_data(AutoResponse, Sock, M) || M <- Messages],
    ok = inet:setopts(Sock, [{active,once}]),
    {noreply, State#state{buffer = Incomplete}};
handle_info({tcp_closed, Sock}, State = #state{sock = Sock}) ->
    ?SYS_WARN("Socket ~p closed.", [Sock]),
    {stop, normal, State};
handle_info({tcp_closed, Socket}, State) ->
    ?SYS_WARN("Unknown socket ~p closed.", [Socket]),
    {stop, normal, State};
handle_info({'EXIT', _, Reason}, State) ->
    {stop, Reason, State};
handle_info(check_send_deliver_sm, State) ->
    case ets:first(get(name)) of
        '$end_of_table' ->
            self() ! check_send_deliver_sm;
        SeqNum ->
            [{SeqNum, Body}] = ets:lookup(get(name), SeqNum),
            Pdu = {?COMMAND_ID_DELIVER_SM, ?ESME_ROK, SeqNum, Body},
            ?SYS_INFO("DELIVER ~p", [Pdu]),
            {ok, BinList} = smpp_operation:pack(Pdu),
            RespBin = list_to_binary(BinList),
            {ok, Reply} = smpp_operation:unpack(RespBin),
            ?SYS_INFO("Sending SMPP request: ~p", [smpp:cmd(Reply)]),
            send_low(State#state.sock, RespBin)
    end,
    {noreply, State};
handle_info(Any, State) ->
    ?SYS_INFO("Unhandled message: ~p", [Any]),
    {noreply, State}.

terminate(Reason, #state{sock = Sock, lsock = undefined}) ->
    case [P || P <- registered(), whereis(P) == self()] of
        [RegName] ->
            ?SYS_INFO("client down ~p : ~p : ~p", [RegName, Reason, Sock]);
        _ ->
            ?SYS_INFO("client down ~p : ~p", [Reason, Sock])
    end;
terminate(Reason, #state{sock = undefined, lsock = LSock}) ->
    ?SYS_INFO("server down ~p : ~p", [Reason, LSock]).

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

handle_data(AutoResponse, Socket, {C,_,SN,B} = Pdu) ->
    case lists:member(C, [?COMMAND_ID_BIND_RECEIVER,
                          ?COMMAND_ID_BIND_TRANSCEIVER,
                          ?COMMAND_ID_BIND_TRANSMITTER]) of
        true ->
            SysId = proplists:get_value(system_id,B),
            TabName = lists:flatten([atom_to_list(?MODULE),"_", SysId]),
            catch ets:new(list_to_atom(TabName), [named_table, public, ordered_set]),
            RegName = list_to_atom(
                        TabName ++
                        case C of
                            ?COMMAND_ID_BIND_RECEIVER -> "_rx";
                            ?COMMAND_ID_BIND_TRANSCEIVER -> "_trx";
                            ?COMMAND_ID_BIND_TRANSMITTER -> "_tx"
                        end),
            erlang:register(RegName, self()),
            put(name, list_to_atom(TabName)),
            if C == ?COMMAND_ID_BIND_RECEIVER ->
                   self() ! check_send_deliver_sm;
               true -> ok
            end,
            ?SYS_INFO("SMSC : ~p", [RegName]);
        false ->
            if C == ?COMMAND_ID_SUBMIT_SM ->
                   true = ets:insert(get(name), {SN, B});
               true -> ok
            end
    end,
    ?SYS_INFO("Req : ~p", [smpp:cmd(Pdu)]),
    if AutoResponse == true ->
           case handle_message(Pdu) of
                {reply, Resp} ->
                    try
                        {ok, BinList} = smpp_operation:pack(Resp),
                        RespBin = list_to_binary(BinList),
                        {ok, Reply} = smpp_operation:unpack(RespBin),
                        ?SYS_INFO("Sending SMPP reply: ~p", [smpp:cmd(Reply)]),
                        send_low(Socket, RespBin)
                    catch
                        _:Error ->
                            ?SYS_ERROR("Error: ~p:~p", [Error,erlang:get_stacktrace()])
                    end;
                _ ->
                    inet:setopts(Socket, [{active, once}])
            end;
       true ->
           inet:setopts(Socket, [{active, once}])
    end.

handle_message({CmdId,Status,SeqNum,Body}) ->
    case CmdId of
        CmdId when CmdId band 16#80000000 == 0 ->
            {reply, {CmdId bor 16#80000000, Status, SeqNum, Body}};
        ?COMMAND_ID_DELIVER_SM_RESP ->
            case catch ets:next(get(name),SeqNum) of
                {'EXIT', _} ->
                    true = ets:delete(get(name), SeqNum),
                    ignore;
                '$end_of_table' ->
                    true = ets:delete(get(name), SeqNum),
                    ignore;
                NextSeqNum ->
                    [{NextSeqNum, Body1}] = ets:lookup(get(name), NextSeqNum),
                    true = ets:delete(get(name), SeqNum),
                    {reply, {?COMMAND_ID_DELIVER_SM, ?ESME_ROK, NextSeqNum, Body1}}
            end;
        _ -> ignore
    end;
handle_message(Pdu) ->
    {reply, Pdu}.

send_low(S, Msg) ->
    gen_tcp:send(S, Msg),
    inet:setopts(S, [{active, once}]).

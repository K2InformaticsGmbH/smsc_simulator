-module(smpp_server).

-include("logger.hrl").
-include_lib("smpp_parser/src/smpp_globals.hrl").

-behaviour(gen_server).
-behaviour(ranch_protocol).

%% gen_server callbacks
-export([init/1,
         handle_call/3,
         handle_cast/2,
         handle_info/2,
         terminate/2,
         code_change/3]).

%% API
-export([start_link/4, try_decode/2]).

-record(state, {sock,  % socket
                transport,
                trn = 0,   % message number
                status,
                buffer, % TCP buffer
                auto_response = true,
                opts,
                conn = {{0,0,0,0},0,{0,0,0,0},0}
               }).

%%%===================================================================
%%% API
%%%===================================================================
start_link(Ref, Sock, Transport, Opts) ->
    {ok, proc_lib:spawn_link(?MODULE, init, [{Ref, Sock, Transport, Opts}])}.

%%%===================================================================
%%% gen_server callbacks
%%%===================================================================

init({Ref, Sock, Transport, Opts}) ->
    ok = ranch:accept_ack(Ref),
    {ok, {RIp, RPort}} = inet:peername(Sock),
    {ok, {LIp, LPort}} = inet:sockname(Sock),
    RIpStr = inet:ntoa(RIp),
    LIpStr = inet:ntoa(LIp),
    ?SYS_INFO("Connect ~s:~p -> ~s:~p", [RIpStr, RPort, LIpStr, LPort]),
    ok = Transport:setopts(Sock, [{active, once}]),
    gen_server:enter_loop(
      ?MODULE, [],
      #state{sock = Sock, transport = Transport, opts = Opts,
             conn = {RIpStr, RPort, LIpStr, LPort}}).

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

handle_cast(stop, State) ->
    {stop, normal, State}.

handle_info({send, Resp}, #state{sock = Sock, transport = Transport} = State) ->
    ok = Transport:setopts(Sock, [{active,once}]),
    ok = Transport:send(Sock, Resp),
    {noreply, State};
handle_info({tcp, Sock, Data},
            State = #state{buffer = B, sock = Sock,
                           transport = Transport,
                           auto_response = AutoResponse}) ->
    ok = Transport:setopts(Sock, [{active,once}]),
    {Messages, Incomplete} = try_decode(Data, B),
    [handle_data(AutoResponse, M) || M <- Messages],
    {noreply, State#state{buffer = Incomplete}};
handle_info({tcp_closed, Sock}, State = #state{sock = Sock}) ->
    {stop, normal, State};
handle_info({tcp_error, _, Reason}, State) ->
	{stop, Reason, State};
handle_info({mo, Mo}, #state{trn = Trn, sock = Sock, transport = Transport} = State) ->
    {ok, Data} = smpp:pack(Mo#{sequence_number => Trn + 1}),
    ok = Transport:setopts(Sock, [{active,once}]),
    ok = Transport:send(Sock, Data),
    {noreply, State#state{trn = Trn + 1}};
handle_info(Any, State) ->
    ?SYS_INFO("Unhandled message: ~p", [Any]),
    {noreply, State}.


terminate(_Reason, #state{conn = {RIpStr, RPort, LIpStr, LPort}}) ->
    ?SYS_INFO("Disconnect ~s:~p -> ~s:~p", [RIpStr, RPort, LIpStr, LPort]).

code_change(_OldVsn, State, _Extra) -> {ok, State}.

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
                    ?SYS_ERROR("Error: {CmdId, Status, SeqNum} ~p",
                               [{CmdId, Status, SeqNum}]),
                    {PDUs, Buffer};
                {'EXIT', Reason} ->
                    ?SYS_ERROR("Error: ~p", [Reason]),
                    {PDUs, Buffer}
            end;
        _ -> {PDUs, Buffer}
    end.

handle_data(true, {CmdId,_,_S,Body} = Pdu) ->
    case CmdId of
       CmdId when CmdId == ?COMMAND_ID_BIND_RECEIVER;
                  CmdId == ?COMMAND_ID_BIND_TRANSCEIVER;
                  CmdId == ?COMMAND_ID_BIND_TRANSMITTER ->
            SysId = proplists:get_value(system_id, Body),
            smpp_simulator:add_route(default, SysId, self());
        ?COMMAND_ID_SUBMIT_SM ->
            Src = proplists:get_value(destination_addr, Body),
            Dst = proplists:get_value(source_addr, Body),
            case smpp_simulator:route(Src, Dst) of
                no_route -> ?SYS_ERROR("no route ~p -> ~p", [Src, Dst]);
                Pid when is_pid(Pid) ->
                    Msg = proplists:get_value(short_message, Body),
                    Pid ! {mo, #{command_id => ?COMMAND_ID_DELIVER_SM,
                                 command_status => ?ESME_ROK,
                                 source_addr => Src, destination_addr => Dst,
                                 short_message => Msg}}
            end;
        _ -> ok
    end,
    case handle_message(Pdu) of
        {reply, Resp} ->
            try
                {ok, BinList} = smpp_operation:pack(Resp),
                RespBin = list_to_binary(BinList),
                self() ! {send, RespBin}
            catch
                _:Error ->
                    ?SYS_ERROR("Error: ~p:~p",
                               [Error,erlang:get_stacktrace()])
            end;
        _ -> ok
    end;
handle_data(false, _) -> ok.

handle_message({CmdId,Status,SeqNum,Body}) ->
    case CmdId of
        CmdId when CmdId band 16#80000000 == 0 ->
            {reply, {CmdId bor 16#80000000, Status, SeqNum, Body}};
        _ -> ignore
    end;
handle_message(Pdu) ->
    {reply, Pdu}.

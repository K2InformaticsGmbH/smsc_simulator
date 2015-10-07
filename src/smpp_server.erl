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
         stop/0,
         send_message/1]).


-define(SERVER, ?MODULE).

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

stop() ->
    gen_server:cast(?SERVER, stop).

send_message(Msg) ->
    gen_server:cast(?SERVER, {send_message, Msg}).

%%%===================================================================
%%% gen_server callbacks
%%%===================================================================

init([LSock]) ->
    ?SYS_INFO("Initializing SMPP server~n", []),
    gen_server:cast(self(), accept),
    {ok, #state{lsock = LSock, trn = 0}}.

handle_call(Msg, From, State) ->
    ?SYS_WARN("Unknown call from (~p): ~p", [From, Msg]),
    {reply, {ok, Msg}, State}.

handle_cast(accept, State = #state{lsock = S}) ->
    {ok, Sock} = gen_tcp:accept(S),
    smpp_simulator_sup:start_child(),
    ?SYS_INFO("Accepting: ~p", [Sock]),
    {noreply, State#state{sock = Sock}};

handle_cast({send_message, _Msg}, State) ->
    % TODO: implement this
    {noreply, State};

handle_cast(stop, State) ->
    {stop, normal, State}.

handle_info({tcp, Socket, Data}, State = #state{buffer = B}) ->
    {Messages, Incomplete} = try_decode(Data, B),
    [handle_data(Socket, M) || M <- Messages],
    {noreply, State#state{buffer = Incomplete}};

handle_info({tcp_closed, Socket}, State) ->
    ?SYS_WARN("Socket ~p closed.", [Socket]),
    smpp_simulator_sup:start_child(),
    {noreply, State};

handle_info(Any, State) ->
    ?SYS_INFO("Unhandled message: ~p", [Any]),
    {noreply, State}.

terminate(_Reason, _State) ->
    ok.

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

handle_data(Socket, Pdu) ->
    ?SYS_INFO("Req : ~p", [cmd(Pdu)]),
    case handle_message(Pdu) of
        {reply, Resp} ->
            try
                {ok, BinList} = smpp_operation:pack(Resp),
                send(Socket, list_to_binary(BinList))
            catch
                _:Error ->
                    ?SYS_ERROR("Error: ~p:~p", [Error,erlang:get_stacktrace()])
            end;
        _ -> ignore
    end.

handle_message({CmdId,Status,SeqNum,Body}) ->
    {reply, {CmdId bor 16#80000000, Status, SeqNum, Body}};
handle_message(Pdu) ->
    {reply, Pdu}.

send(S, Msg) ->
    gen_tcp:send(S, Msg),
    inet:setopts(S, [{active, once}]).

cmd({?COMMAND_ID_UNBIND,                      _S,_SN,_B})    -> unbind;
cmd({?COMMAND_ID_OUTBIND,                     _S,_SN,_B})    -> outbind;
cmd({?COMMAND_ID_DATA_SM,                     _S,_SN,_B})    -> data_sm;
cmd({?COMMAND_ID_QUERY_SM,                    _S,_SN,_B})    -> query_sm;
cmd({?COMMAND_ID_CANCEL_SM,                   _S,_SN,_B})    -> cancel_sm;
cmd({?COMMAND_ID_SUBMIT_SM,                   _S,_SN,_B})    -> submit_sm;
cmd({?COMMAND_ID_REPLACE_SM,                  _S,_SN,_B})    -> replace_sm;
cmd({?COMMAND_ID_DELIVER_SM,                  _S,_SN,_B})    -> deliver_sm;
cmd({?COMMAND_ID_SUBMIT_MULTI,                _S,_SN,_B})    -> submit_multi;
cmd({?COMMAND_ID_BROADCAST_SM,                _S,_SN,_B})    -> broadcast_sm;
cmd({?COMMAND_ID_ENQUIRE_LINK,                _S,_SN,_B})    -> enquire_link;
cmd({?COMMAND_ID_GENERIC_NACK,                _S,_SN,_B})    -> generic_nack;
cmd({?COMMAND_ID_BIND_RECEIVER,               _S,_SN,_B})    -> bind_receiver;
cmd({?COMMAND_ID_BIND_TRANSCEIVER,            _S,_SN,_B})    -> bind_transceiver;
cmd({?COMMAND_ID_BIND_TRANSMITTER,            _S,_SN,_B})    -> bind_transmitter;
cmd({?COMMAND_ID_ALERT_NOTIFICATION,          _S,_SN,_B})    -> alert_notification;
cmd({?COMMAND_ID_QUERY_BROADCAST_SM,          _S,_SN,_B})    -> query_broadcast_sm;
cmd({?COMMAND_ID_CANCEL_BROADCAST_SM,         _S,_SN,_B})    -> cancel_broadcast_sm;

cmd({?COMMAND_ID_UNBIND_RESP,                 _S,_SN,_B})    -> unbind_resp;
cmd({?COMMAND_ID_DATA_SM_RESP,                _S,_SN,_B})    -> data_sm_resp;
cmd({?COMMAND_ID_QUERY_SM_RESP,               _S,_SN,_B})    -> query_sm_resp;
cmd({?COMMAND_ID_SUBMIT_SM_RESP,              _S,_SN,_B})    -> submit_sm_resp;
cmd({?COMMAND_ID_CANCEL_SM_RESP,              _S,_SN,_B})    -> cancel_sm_resp;
cmd({?COMMAND_ID_REPLACE_SM_RESP,             _S,_SN,_B})    -> replace_sm_resp;
cmd({?COMMAND_ID_DELIVER_SM_RESP,             _S,_SN,_B})    -> deliver_sm_resp;
cmd({?COMMAND_ID_SUBMIT_MULTI_RESP,           _S,_SN,_B})    -> submit_multi_resp;
cmd({?COMMAND_ID_BROADCAST_SM_RESP,           _S,_SN,_B})    -> broadcast_sm_resp;
cmd({?COMMAND_ID_ENQUIRE_LINK_RESP,           _S,_SN,_B})    -> enquire_link_resp;
cmd({?COMMAND_ID_BIND_RECEIVER_RESP,          _S,_SN,_B})    -> bind_receiver_resp;
cmd({?COMMAND_ID_BIND_TRANSCEIVER_RESP,       _S,_SN,_B})    -> bind_transceiver_resp;
cmd({?COMMAND_ID_BIND_TRANSMITTER_RESP,       _S,_SN,_B})    -> bind_transmitter_resp;
cmd({?COMMAND_ID_QUERY_BROADCAST_SM_RESP,     _S,_SN,_B})    -> query_broadcast_sm_resp;
cmd({?COMMAND_ID_CANCEL_BROADCAST_SM_RESP,    _S,_SN,_B})    -> cancel_broadcast_sm_resp.

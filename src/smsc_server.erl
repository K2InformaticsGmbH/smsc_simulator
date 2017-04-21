-module(smsc_server).

-include("logger.hrl").
-include_lib("smpp_parser/src/smpp_globals.hrl").
-include_lib("ucp_parser/src/ucp_defines.hrl").

-behaviour(gen_server).
-behaviour(ranch_protocol).

%% gen_server callbacks
-export([init/1,
         handle_call/3,
         handle_cast/2,
         handle_info/2,
         terminate/2,
         code_change/3]).

%% TPI-Cowboy
-export([init/2]).

%% API
-export([start_link/4]).

-record(state, {sock,  % socket
                transport,
                trn = 0,   % message number
                status,
                buffer, % TCP buffer
                auto_response = true,
                proto,
                conn = {{0,0,0,0},0,{0,0,0,0},0}
               }).

%%%===================================================================
%%% API
%%%===================================================================

start_link(Ref, Sock, Transport, [Proto]) ->
    {ok, proc_lib:spawn_link(?MODULE, init, [{Ref, Sock, Transport, Proto}])}.

%%%===================================================================
%%% gen_server callbacks
%%%===================================================================

init({Ref, Sock, Transport, Proto}) ->
    ok = ranch:accept_ack(Ref),
    {ok, {RIp, RPort}} = inet:peername(Sock),
    {ok, {LIp, LPort}} = inet:sockname(Sock),
    RIpStr = inet:ntoa(RIp),
    LIpStr = inet:ntoa(LIp),
    ?SYS_INFO("[~p] connect ~s:~p -> ~s:~p", [Proto, RIpStr, RPort, LIpStr, LPort]),
    ok = Transport:setopts(Sock, [{active, once}]),
    gen_server:enter_loop(
      ?MODULE, [],
      #state{sock = Sock, transport = Transport, proto = Proto,
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
            State = #state{buffer = B, sock = Sock, transport = Transport,
                           proto = Proto, auto_response = AutoResponse}) ->
    ok = Transport:setopts(Sock, [{active,once}]),
    {Messages, Incomplete} = try_decode(Proto, Data, B),
    [handle_data(Proto, AutoResponse, M) || M <- Messages],
    {noreply, State#state{buffer = Incomplete}};
handle_info({tcp_closed, Sock}, State = #state{sock = Sock}) ->
    {stop, normal, State};
handle_info({tcp_error, _, Reason}, State) ->
	{stop, Reason, State};
handle_info({mo, Mo}, #state{proto = smpp, trn = Trn, sock = Sock,
                             transport = Transport} = State) ->
    {ok, Data} = smpp:pack(Mo#{sequence_number => Trn}),
    ok = Transport:setopts(Sock, [{active,once}]),
    ok = Transport:send(Sock, Data),
    {noreply, State#state{trn = Trn + 1}};
handle_info({mo, Mo}, #state{trn = Trn, sock = Sock, transport = Transport,
                             proto = ucp} = State) ->
    Data = list_to_binary(ucp:pack([{trn, Trn} | Mo])),
    ok = Transport:setopts(Sock, [{active, once}]),
    ok = Transport:send(Sock, Data),
    {noreply, State#state{trn = if Trn + 1 > 99 -> (#state{})#state.trn;
                                   true -> Trn + 1 end}};
handle_info(Any, State) ->
    ?SYS_INFO("Unhandled message: ~p", [Any]),
    {noreply, State}.

terminate(_Reason, #state{conn = {RIpStr, RPort, LIpStr, LPort}, proto = Proto}) ->
    ?SYS_INFO("[~p] disconnect ~s:~p -> ~s:~p", [Proto, RIpStr, RPort, LIpStr, LPort]).

code_change(_OldVsn, State, _Extra) -> {ok, State}.

%%%===================================================================
%%% Internal functions
%%%===================================================================

try_decode(Proto, Data, undefined) when is_binary(Data) ->
    try_decode(Proto, Data, []);
try_decode(Proto, Data, B) when is_binary(Data), is_binary(B) ->
    try_decode(Proto, <<Data/binary, B/binary>>, []);
try_decode(_, <<>>, PDUs) when is_list(PDUs) -> {PDUs, <<>>};
try_decode(smpp, <<CmdLen:32, Rest/binary>> = Buffer, PDUs) when is_list(PDUs) ->
    Len = CmdLen - 4,
    case Rest of
        <<PduRest:Len/binary-unit:8, NextPdus/binary>> ->
            BinPdu = <<CmdLen:32, PduRest/binary>>,
            case catch smpp_operation:unpack(BinPdu) of
                {ok, Pdu} ->
                    try_decode(smpp, NextPdus, PDUs++[Pdu]);
                {error, CmdId, Status, SeqNum} ->
                    ?SYS_ERROR("Error: {CmdId, Status, SeqNum} ~p",
                               [{CmdId, Status, SeqNum}]),
                    {PDUs, Buffer};
                {'EXIT', Reason} ->
                    ?SYS_ERROR("Error: ~p", [Reason]),
                    {PDUs, Buffer}
            end;
        _ -> {PDUs, Buffer}
    end;
try_decode(ucp, <<2, _/binary>> = Buffer, PDUs) when is_list(PDUs) ->
   case ucp:parse_stream(Buffer) of
       {BinPduList, Rest} ->
           {[Pdu || {_, Pdu} <- BinPduList] ++ PDUs, Rest}
   end.

handle_data(smpp, true, {CmdId,Status,SeqNum,Body}) ->
    case CmdId of
       CmdId when CmdId == ?COMMAND_ID_BIND_RECEIVER;
                  CmdId == ?COMMAND_ID_BIND_TRANSCEIVER;
                  CmdId == ?COMMAND_ID_BIND_TRANSMITTER ->
            SysId = proplists:get_value(system_id, Body),
            smsc_simulator:add_route(default, SysId, self());
        ?COMMAND_ID_SUBMIT_SM ->
            Src = proplists:get_value(destination_addr, Body),
            Dst = proplists:get_value(source_addr, Body),
            case smsc_simulator:route(Src) of
                Pid when is_pid(Pid) ->
                    Msg = proplists:get_value(short_message, Body),
                    Pid ! {mo, #{command_id => ?COMMAND_ID_DELIVER_SM,
                                 command_status => ?ESME_ROK,
                                 source_addr => Src, destination_addr => Dst,
                                 short_message => Msg}};
                BadRoute -> ?SYS_ERROR("~p ~p -> ~p", [BadRoute, Src, Dst])
            end;
        _ -> ok
    end,
    if CmdId band 16#80000000 == 0 ->
           try
               {ok, BinList} = smpp_operation:pack(
                                 {CmdId bor 16#80000000, Status, SeqNum, Body}),
               RespBin = list_to_binary(BinList),
               self() ! {send, RespBin}
           catch
               _:Error ->
                   ?SYS_ERROR("Error: ~p:~p", [Error,erlang:get_stacktrace()])
           end;
       true -> nop
    end;
handle_data(ucp, true, Pdu) ->
    Cmd = proplists:get_value(ot, Pdu),
    Type = proplists:get_value(type, Pdu),
    case {Cmd, Type} of
        {?UCP_OT_SESSION_MANAGEMENT, "O"} ->
            OAdc = proplists:get_value(oadc, Pdu),
            smsc_simulator:add_route(default, OAdc, self());
        {?UCP_OT_SUBMIT_SM, "O"} ->
            Src = proplists:get_value(adc, Pdu),
            Dst = proplists:get_value(oadc, Pdu),
            case smsc_simulator:route(Src) of
                Pid when is_pid(Pid) ->
                    Msg = proplists:get_value(msg, Pdu, []),
                    Pid ! {mo, [{ot,?UCP_OT_CALL_INPUT}, {type,"O"},
                                {oadc, Src}, {adc, Dst}, {msg, Msg}, {mt,3}]};
                BadRoute -> ?SYS_ERROR("~p ~p -> ~p", [BadRoute, Src, Dst])
            end;
        _ -> ok
    end,
    case Type of
        "O" -> self() ! {send, list_to_binary(ucp_syntax:make_ack(Pdu))};
        "R" -> nop
    end;
handle_data(_, false, _) -> ok.


%%%===================================================================
%%% TPI-Cowboy callbacks
%%%===================================================================

init(Req0 = #{method := <<"POST">>, has_body := true}, DsPort) ->
    #{peer := {PeerIp,_}} = Req0,
    {ok, Data, Req1} = cowboy_req:read_body(Req0),
    {match, [ShortId, TrnId, FwdHost, Recipient]} =
    re:run(Data,
           "<short-id>([0-9]+)</short-id>.*"
           "<transaction-id>([0-9]+)</transaction-id>.*"
           "<report-address>([^ ]+)</report-address>.*"
           "<recipient field=\"to\">([0-9]+)</recipient>",
           [dotall, {capture, [1,2,3,4], list}]),
    MsgId = erlang:unique_integer([positive]),
    Req = cowboy_req:reply(
            200, #{<<"content-type">> => <<"text/xml">>},
            list_to_binary(
                io_lib:format(
                    "<?xml version=\"1.0\" encoding=\"UTF-8\"?>"
                    "<soapenv:Envelope>"
                     "<soapenv:Body>"
                         "<SMSSubmitResponse>"
                             "<transaction-id>~s</transaction-id>"
                             "<state>1000</state>"
                             "<state-text>Ok</state-text>"
                             "<message-id>~p</message-id>"
                             "<message-state recipient=~p state=\"0\" state-text=\"Ok\"/>"
                             "<message-type>SMSSubmitResponse</message-type>"
                         "</SMSSubmitResponse>"
                     "</soapenv:Body>"
                    "</soapenv:Envelope>",
                     [TrnId, MsgId, Recipient])), Req1),
    Host = inet:ntoa(PeerIp),
    % report
    spawn(
      fun() ->
        Url = lists:concat(
                ["http://",Host,":",DsPort,"/?ShortID=",ShortId,
                 "&reportType=DELIVERY&msgId=",MsgId,"&recipient=",Recipient,
                 "&msgState=0&msgStateText=Retrieved"]),
        case catch httpc:request(get, {Url, [{"Connection","close"},
                                             {"Host", FwdHost}]}, [], []) of
            {ok, {{_, 200, _}, _, _}} -> ok;
            {'EXIT', Error} -> lager:error("CRASH report ~p, ~p", [Url, Error]);
            {error, Reason} -> lager:error("report ~p : ~p", [Url, Reason]);
            {ok, {_, Code, _}, _, Body} ->
                lager:info("ERROR report ~p : {~p,~s}", [Url, Code, Body])
        end
      end),

    % delivery
    spawn(
      fun() ->
        Url = lists:concat(["http://",Host,":",DsPort,"/deliver"]),
        case catch httpc:request(
                     post, {Url, [{"Connection","close"}, {"Host", FwdHost}],
                            "multipart/related; boundary=part_boundary",
            list_to_binary(
                io_lib:format(
                  "--part_boundary\r\n"
                  "Content-Type: text/xml; charset=UTF-8\r\n"
                  "Content-Transfer-Encoding: binary\r\n"
                  "\r\n"
                  "<?xml version=\"1.0\" encoding=\"UTF-8\"?>"
                  "<soapenv:Envelope>"
                      "<soapenv:Body>"
                          "<SMSDeliverRequest>"
                              "<transaction-id>~s</transaction-id>"
                              "<from>~s</from>"
                              "<recipient>~s</recipient>"
                              "<message-type>SMSDeliverRequest</message-type>"
                          "</SMSDeliverRequest>"
                      "</soapenv:Body>"
                  "</soapenv:Envelope>\r\n"
                  "\r\n"
                  "--part_boundary\r\n"
                  "Content-Type: text/plain; charset=\"utf-8\"\r\n"
                  "Content-Id: <0>\r\n"
                  "\r\n"
                  "~p\r\n"
                  "--part_boundary--\r\n",
                  [TrnId, Recipient, ShortId, os:timestamp()]))}, [], []) of
            {ok, {{_, 200, _}, _, _}} -> ok;
            {'EXIT', Error} -> lager:error("CRASH deliver ~p, ~p", [Url, Error]);
            {error, Reason} -> lager:error("deliver ~p : ~p", [Url, Reason]);
            {ok, {_, Code, _}, _, Body} ->
                lager:info("ERROR deliver ~p : {~p,~s}", [Url, Code, Body])
        end
      end),
    {ok, Req, DsPort}.

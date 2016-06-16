SMPP simulator - A hunky Erlang emulating SMPP protocol server
================================================================================

The simulator is an application for near-to-live testing of your SMPP
applications without need of access to real SMSC. The application behaves as
a real SMSC with SMPP interface. Your application can bind to it, send messages,
etc., however nothing will get delivered anywhere as all the responses are
only made-up by the simulator.

If you like this project, you might also be interested in [jtendo UCP Gateway](https://github.com/jtendo/ucp_gateway)

Configuration
-------------

- `listen_port`: the listening port (default: 8888)

Example
-------
```erlang
%% Client
%% ------
smpp_client:stop("4115").
smpp_client:start("4115", {127,0,0,1}, 4040).
smpp_client:bind("4115").

smpp_client:send("4115", deliver_sm_resp, 1, []).
smpp_client:send("4115", deliver_sm_resp, 8, []).

smpp_client:stop("4115").

%% Server
%% ------
smpp_simulator:restart().
smpp_server:send_message(smpp_server_4115, 1, 41794519635, 4115, "this is a test").

[smpp_server:send_message(smpp_server_4115, I, 41794519635, 4115, "this is a test") || I <- lists:seq(1,10)].

```

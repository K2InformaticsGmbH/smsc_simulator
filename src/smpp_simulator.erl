-module(smpp_simulator).
-license("New BSD License, see LICENSE for details").

-export([start/0]).

%% @doc Start the application. Mainly useful for using `-s smpp_simulator' as a command
%% line switch to the VM to make smpp_simulator start on boot.
start() ->
    application:start(smpp_simulator).


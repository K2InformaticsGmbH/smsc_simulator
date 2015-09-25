#!/bin/bash

unamestr=`uname`
if [[ "$unamestr" == 'Linux' ]]; then
     exename=erl
else
    exename='start //MAX werl.exe'
    #exename='erl.exe'
fi

listen_port="-ucp_simulator listen_port $1"
if [ "$#" -ne 1 ]; then
    listen_port=""
fi

$exename -pa deps/*/ebin -pa ebin $listen_port -boot start_sasl -s lager -s ucp_simulator_app

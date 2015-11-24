#!/bin/bash

unamestr=`uname`
if [[ "$unamestr" == 'Linux' ]]; then
     exename=erl
else
    exename='start //MAX werl.exe'
    #exename='erl.exe'
fi

listen_port="-smpp_simulator listen_port $1"
if [ "$#" -ne 1 ]; then
    listen_port=""
fi

MY_PATH="`dirname \"$0\"`"              # relative
MY_PATH="`( cd \"$MY_PATH\" && pwd )`"  # absolutized and normalized
if [ -z "$MY_PATH" ] ; then
  # error; for some reason, the path is not accessible
  # to the script (e.g. permissions re-evaled after suid)
  exit 1  # fail
fi

$exename -sname $1_smpp -pa $MY_PATH/deps/*/ebin -pa $MY_PATH/ebin $listen_port -boot start_sasl -s lager -s smpp_simulator_app

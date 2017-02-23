#!/bin/bash

me=`basename "$0"`
if [[ $# -ne 1 ]]; then
    echo "usage : $me nde_id"
    exit
fi

unamestr=`uname`
if [[ "$unamestr" == 'Linux' ]]; then
     exename=erl
else
    exename='start //MAX werl.exe'
    #exename='erl.exe'
fi

MY_PATH="`dirname \"$0\"`"              # relative
MY_PATH="`( cd \"$MY_PATH\" && pwd )`"  # absolutized and normalized
if [ -z "$MY_PATH" ] ; then
  # error; for some reason, the path is not accessible
  # to the script (e.g. permissions re-evaled after suid)
  exit 1  # fail
fi

$exename -name smpp_smsc$1@127.0.0.1 -setcookie smpp_smsc_simulator -pa $MY_PATH/deps/*/ebin -pa $MY_PATH/ebin -sasl sasl_error_logger false -boot start_sasl -s lager -s smpp_simulator

#!/bin/bash

ck=smsc_simulator
imemtyp=disc
me=`basename "$0"`
if [[ $# -lt 1 ]]; then
    echo "usage : $me nde_id [host_ip]"
    exit
fi

host=127.0.0.1
if [[ $# -gt 1 ]]; then
    host=$2
fi

name=smsc$1@$host
unamestr=`uname`
if [[ "$unamestr" == 'Linux' ]]; then
     exename=erl
else
    exename='start //MAX werl.exe'
    #exename='erl.exe'
fi

# Node name
node_name="-name $name"

# Cookie
cookie="-setcookie $ck"

# PATHS
paths="-pa"
paths=$paths" _build/default/lib/*/ebin"

# sasl opts
sasl_opts="-sasl"
sasl_opts=$sasl_opts"  sasl_error_logger false" 

# boot
boot="-boot"
boot=$boot" start_sasl" 

# apps
apps="-s lager"
apps=$apps""

start_opts="$paths $cookie $node_name $sasl_opts $boot $apps"

# CPRO start options
echo "------------------------------------------"
echo "Starting SMSC Simulator"
echo "------------------------------------------"
echo "Node Name : $node_name"
echo "Cookie    : $cookie"
echo "EBIN Path : $paths"
echo "SASL      : $sasl_opts"
echo "BOOT      : $boot"
echo "APPS      : $apps"
echo "------------------------------------------"

# Starting cpro
$exename $start_opts -s smsc_simulator

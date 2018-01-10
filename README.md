SMSC simulator - A SMPP/UCP protocols server
================================================================================

The simulator is an application for near-to-live testing of your SMPP/UCP
applications without need of access to real SMSC. The application behaves as
a real SMSC with SMPP/UCP interfaces. Your application can bind to it, send messages,
etc., however nothing will get delivered anywhere as all the responses are
only made-up by the simulator.

Usage
-----
Start the VM with supplied start script [`start.sh`](https://github.com/K2InformaticsGmbH/smsc_simulator/blob/master/start.sh)
```sh
$ ./start.sh
usage : start.sh nde_id
nde_id : integer node ID used to distinguish multiple erlang nodes in same esystem if so required to be started
$ ./start.sh 1
```
```erlang
Erlang/OTP 18 [erts-7.0] [64-bit] [smp:4:4] [async-threads:10]

Eshell V7.0  (abort with ^G)
(smsc1@127.0.0.1)1> 15:52:01.580 [info] Application lager started on node 'smsc1@127.0.0.1'
15:52:01.598 [info] Application crypto started on node 'smsc1@127.0.0.1'
15:52:01.620 [info] Application asn1 started on node 'smsc1@127.0.0.1'
15:52:01.620 [info] Application public_key started on node 'smsc1@127.0.0.1'
15:52:01.639 [info] Application ssl started on node 'smsc1@127.0.0.1'
15:52:01.643 [info] Application ranch started on node 'smsc1@127.0.0.1'
15:52:01.644 [info] Application smpp_parser started on node 'smsc1@127.0.0.1'
15:52:01.645 [info] Application ucp_parser started on node 'smsc1@127.0.0.1'
15:52:02.199 [info] Application lager started on node 'smpp_smsc_db@127.0.0.1'
15:52:02.303 [info] Application mnesia started on node 'smpp_smsc_db@127.0.0.1'
15:52:02.326 [info] starting MASTER for DB node 'smpp_smsc_db@127.0.0.1'
15:52:02.329 [info] subscribed to routing table chnages...
15:52:02.438 [info] Application mnesia started on node 'smsc1@127.0.0.1'
15:52:02.471 [info] Application smsc_simulator started on node 'smsc1@127.0.0.1'
```

In `smscX` VM node(s) start/stop SMSCs
```erlang
(smsc1@127.0.0.1)2> smsc_simulator:start(smpp,10000). % Protocol, Port (multiple and independent)
{ok,<0.145.0>}
(smsc1@127.0.0.1)3> 15:56:25.334 [info] [smsc_server:47] [smpp] connect 127.0.0.1:60084 -> 127.0.0.1:10000

(smsc1@127.0.0.1)3> smsc_simulator:stop(10000).      
ok

```

Message Routing management
```erlang
(smsc1@127.0.0.1)7> smsc_simulator:add_route("0790000000","1234").

(smsc1@127.0.0.1)7> smsc_simulator:all_routes().
[{router,"0790000000","1234",undefined}]

(smsc1@127.0.0.1)7> smsc_simulator:del_route("0790000000").
(smsc1@127.0.0.1)7> smsc_simulator:all_routes().
[]
```

## Docker

### Build Docker Image

```bash
cd smsc_simulator
docker build -t smsc_simulator:latest .
```

### Run Docker Container (Example)

Start a container and expose the ports for smpp and ucp:
```bash
docker run -ti --rm --name smsc1 \
  -e NDE_ID=1 \
  -p 10000:10000 \
  -p 10001:10001 \
  smsc_simulator:latest
```

Start the listeners for smpp and ucp when container is started:
```erlang
smsc_simulator:start(smpp,10000).
smsc_simulator:start(ucp,10001).
```

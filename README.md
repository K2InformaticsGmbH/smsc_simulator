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

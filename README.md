SMSC simulator - A hunky Erlang emulating SMPP/UCP protocols server
================================================================================

The simulator is an application for near-to-live testing of your SMPP/UCP
applications without need of access to real SMSC. The application behaves as
a real SMSC with SMPP/UCP interfaces. Your application can bind to it, send messages,
etc., however nothing will get delivered anywhere as all the responses are
only made-up by the simulator.

Example
-------
```erlang
```

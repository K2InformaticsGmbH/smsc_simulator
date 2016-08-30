-module(smpp).
-include("smpp_parser/smpp_globals.hrl").

-export([cmd/1]).

cmd({unbind,S,SN,B})                     -> {?COMMAND_ID_UNBIND,                      S,SN,B};
cmd({outbind,S,SN,B})                    -> {?COMMAND_ID_OUTBIND,                     S,SN,B};
cmd({data_sm,S,SN,B})                    -> {?COMMAND_ID_DATA_SM,                     S,SN,B};
cmd({query_sm,S,SN,B})                   -> {?COMMAND_ID_QUERY_SM,                    S,SN,B};
cmd({cancel_sm,S,SN,B})                  -> {?COMMAND_ID_CANCEL_SM,                   S,SN,B};
cmd({submit_sm,S,SN,B})                  -> {?COMMAND_ID_SUBMIT_SM,                   S,SN,B};
cmd({replace_sm,S,SN,B})                 -> {?COMMAND_ID_REPLACE_SM,                  S,SN,B};
cmd({deliver_sm,S,SN,B})                 -> {?COMMAND_ID_DELIVER_SM,                  S,SN,B};
cmd({submit_multi,S,SN,B})               -> {?COMMAND_ID_SUBMIT_MULTI,                S,SN,B};
cmd({broadcast_sm,S,SN,B})               -> {?COMMAND_ID_BROADCAST_SM,                S,SN,B};
cmd({enquire_link,S,SN,B})               -> {?COMMAND_ID_ENQUIRE_LINK,                S,SN,B};
cmd({generic_nack,S,SN,B})               -> {?COMMAND_ID_GENERIC_NACK,                S,SN,B};
cmd({bind_receiver,S,SN,B})              -> {?COMMAND_ID_BIND_RECEIVER,               S,SN,B};
cmd({bind_transceiver,S,SN,B})           -> {?COMMAND_ID_BIND_TRANSCEIVER,            S,SN,B};
cmd({bind_transmitter,S,SN,B})           -> {?COMMAND_ID_BIND_TRANSMITTER,            S,SN,B};
cmd({alert_notification,S,SN,B})         -> {?COMMAND_ID_ALERT_NOTIFICATION,          S,SN,B};
cmd({query_broadcast_sm,S,SN,B})         -> {?COMMAND_ID_QUERY_BROADCAST_SM,          S,SN,B};
cmd({cancel_broadcast_sm,S,SN,B})        -> {?COMMAND_ID_CANCEL_BROADCAST_SM,         S,SN,B};
                                                       
cmd({unbind_resp,S,SN,B})                -> {?COMMAND_ID_UNBIND_RESP,                 S,SN,B};
cmd({data_sm_resp,S,SN,B})               -> {?COMMAND_ID_DATA_SM_RESP,                S,SN,B};
cmd({query_sm_resp,S,SN,B})              -> {?COMMAND_ID_QUERY_SM_RESP,               S,SN,B};
cmd({submit_sm_resp,S,SN,B})             -> {?COMMAND_ID_SUBMIT_SM_RESP,              S,SN,B};
cmd({cancel_sm_resp,S,SN,B})             -> {?COMMAND_ID_CANCEL_SM_RESP,              S,SN,B};
cmd({replace_sm_resp,S,SN,B})            -> {?COMMAND_ID_REPLACE_SM_RESP,             S,SN,B};
cmd({deliver_sm_resp,S,SN,B})            -> {?COMMAND_ID_DELIVER_SM_RESP,             S,SN,B};
cmd({submit_multi_resp,S,SN,B})          -> {?COMMAND_ID_SUBMIT_MULTI_RESP,           S,SN,B};
cmd({broadcast_sm_resp,S,SN,B})          -> {?COMMAND_ID_BROADCAST_SM_RESP,           S,SN,B};
cmd({enquire_link_resp,S,SN,B})          -> {?COMMAND_ID_ENQUIRE_LINK_RESP,           S,SN,B};
cmd({bind_receiver_resp,S,SN,B})         -> {?COMMAND_ID_BIND_RECEIVER_RESP,          S,SN,B};
cmd({bind_transceiver_resp,S,SN,B})      -> {?COMMAND_ID_BIND_TRANSCEIVER_RESP,       S,SN,B};
cmd({bind_transmitter_resp,S,SN,B})      -> {?COMMAND_ID_BIND_TRANSMITTER_RESP,       S,SN,B};
cmd({query_broadcast_sm_resp,S,SN,B})    -> {?COMMAND_ID_QUERY_BROADCAST_SM_RESP,     S,SN,B};
cmd({cancel_broadcast_sm_resp,S,SN,B})   -> {?COMMAND_ID_CANCEL_BROADCAST_SM_RESP,    S,SN,B};

cmd({?COMMAND_ID_UNBIND,                      S,SN,B})    -> {unbind,S,SN,B};
cmd({?COMMAND_ID_OUTBIND,                     S,SN,B})    -> {outbind,S,SN,B};
cmd({?COMMAND_ID_DATA_SM,                     S,SN,B})    -> {data_sm,S,SN,B};
cmd({?COMMAND_ID_QUERY_SM,                    S,SN,B})    -> {query_sm,S,SN,B};
cmd({?COMMAND_ID_CANCEL_SM,                   S,SN,B})    -> {cancel_sm,S,SN,B};
cmd({?COMMAND_ID_SUBMIT_SM,                   S,SN,B})    -> {submit_sm,S,SN,B};
cmd({?COMMAND_ID_REPLACE_SM,                  S,SN,B})    -> {replace_sm,S,SN,B};
cmd({?COMMAND_ID_DELIVER_SM,                  S,SN,B})    -> {deliver_sm,S,SN,B};
cmd({?COMMAND_ID_SUBMIT_MULTI,                S,SN,B})    -> {submit_multi,S,SN,B};
cmd({?COMMAND_ID_BROADCAST_SM,                S,SN,B})    -> {broadcast_sm,S,SN,B};
cmd({?COMMAND_ID_ENQUIRE_LINK,                S,SN,B})    -> {enquire_link,S,SN,B};
cmd({?COMMAND_ID_GENERIC_NACK,                S,SN,B})    -> {generic_nack,S,SN,B};
cmd({?COMMAND_ID_BIND_RECEIVER,               S,SN,B})    -> {bind_receiver,S,SN,B};
cmd({?COMMAND_ID_BIND_TRANSCEIVER,            S,SN,B})    -> {bind_transceiver,S,SN,B};
cmd({?COMMAND_ID_BIND_TRANSMITTER,            S,SN,B})    -> {bind_transmitter,S,SN,B};
cmd({?COMMAND_ID_ALERT_NOTIFICATION,          S,SN,B})    -> {alert_notification,S,SN,B};
cmd({?COMMAND_ID_QUERY_BROADCAST_SM,          S,SN,B})    -> {query_broadcast_sm,S,SN,B};
cmd({?COMMAND_ID_CANCEL_BROADCAST_SM,         S,SN,B})    -> {cancel_broadcast_sm,S,SN,B};

cmd({?COMMAND_ID_UNBIND_RESP,                 S,SN,B})    -> {unbind_resp,S,SN,B};
cmd({?COMMAND_ID_DATA_SM_RESP,                S,SN,B})    -> {data_sm_resp,S,SN,B};
cmd({?COMMAND_ID_QUERY_SM_RESP,               S,SN,B})    -> {query_sm_resp,S,SN,B};
cmd({?COMMAND_ID_SUBMIT_SM_RESP,              S,SN,B})    -> {submit_sm_resp,S,SN,B};
cmd({?COMMAND_ID_CANCEL_SM_RESP,              S,SN,B})    -> {cancel_sm_resp,S,SN,B};
cmd({?COMMAND_ID_REPLACE_SM_RESP,             S,SN,B})    -> {replace_sm_resp,S,SN,B};
cmd({?COMMAND_ID_DELIVER_SM_RESP,             S,SN,B})    -> {deliver_sm_resp,S,SN,B};
cmd({?COMMAND_ID_SUBMIT_MULTI_RESP,           S,SN,B})    -> {submit_multi_resp,S,SN,B};
cmd({?COMMAND_ID_BROADCAST_SM_RESP,           S,SN,B})    -> {broadcast_sm_resp,S,SN,B};
cmd({?COMMAND_ID_ENQUIRE_LINK_RESP,           S,SN,B})    -> {enquire_link_resp,S,SN,B};
cmd({?COMMAND_ID_BIND_RECEIVER_RESP,          S,SN,B})    -> {bind_receiver_resp,S,SN,B};
cmd({?COMMAND_ID_BIND_TRANSCEIVER_RESP,       S,SN,B})    -> {bind_transceiver_resp,S,SN,B};
cmd({?COMMAND_ID_BIND_TRANSMITTER_RESP,       S,SN,B})    -> {bind_transmitter_resp,S,SN,B};
cmd({?COMMAND_ID_QUERY_BROADCAST_SM_RESP,     S,SN,B})    -> {query_broadcast_sm_resp,S,SN,B};
cmd({?COMMAND_ID_CANCEL_BROADCAST_SM_RESP,    S,SN,B})    -> {cancel_broadcast_sm_resp,S,SN,B}.

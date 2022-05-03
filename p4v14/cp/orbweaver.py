import sys
import argparse
import importlib
import json
import os
import signal
import time
from collections import OrderedDict
import logging
import copy
import pdb
import unittest
import random
import statistics

from thrift.transport import TSocket
from thrift.transport import TTransport
from thrift.protocol import TBinaryProtocol
from thrift.protocol import TMultiplexedProtocol

sys.path.append("/home/leoyu/bf-sde-9.2.0/install/lib/python2.7/site-packages/tofino/")
sys.path.append("/home/leoyu/bf-sde-9.2.0/install/lib/python2.7/site-packages/")

import pal_rpc.pal as pal_i
from pal_rpc.ttypes import *
import mirror_pd_rpc.mirror as mirror_i
from mirror_pd_rpc.ttypes import *
import conn_mgr_pd_rpc.conn_mgr as conn_mgr_client_module
import mc_pd_rpc.mc as mc_client_module
from res_pd_rpc.ttypes import *
from ptf.thriftutils import *

from utils.helper import *


class Controller:
  def __init__(self, prog_name):
    
    self.prog_name = prog_name

    self.transport = TSocket.TSocket('localhost', 9090)
    self.transport = TTransport.TBufferedTransport(self.transport)
    self.bprotocol = TBinaryProtocol.TBinaryProtocol(self.transport)
    self.transport.open()

    self.bw_dict = {"10G":pal_port_speed_t.BF_SPEED_10G, 
                    "40G":pal_port_speed_t.BF_SPEED_40G, 
	            "25G":pal_port_speed_t.BF_SPEED_25G,
		    "100G":pal_port_speed_t.BF_SPEED_100G}
    self.fec_dict = {"NONE" :pal_fec_type_t.BF_FEC_TYP_NONE,
                     "FC" : pal_fec_type_t.BF_FEC_TYP_FIRECODE,
		     "RS" : pal_fec_type_t.BF_FEC_TYP_REED_SOLOMON}

    self.pal_protocol = TMultiplexedProtocol.TMultiplexedProtocol(self.bprotocol, "pal")
    self.pal = pal_i.Client(self.pal_protocol)

    self.mirror_protocol = TMultiplexedProtocol.TMultiplexedProtocol(self.bprotocol, "mirror")
    self.mirror = mirror_i.Client(self.mirror_protocol)

    pd_path = "/home/leoyu/bf-sde-9.2.0/install/lib/python2.7/site-packages/tofinopd/"+self.prog_name
    sys.path.insert(0, pd_path)
    self.dp_client_module = importlib.import_module("p4_pd_rpc."+self.prog_name)
#    print(dir(self.dp_client_module))
    self.dp_ttypes = importlib.import_module("p4_pd_rpc.ttypes")

    self.p4_protocol = TMultiplexedProtocol.TMultiplexedProtocol(self.bprotocol, prog_name)
    self.client = self.dp_client_module.Client(self.p4_protocol)
    self.conn_mgr_protocol = TMultiplexedProtocol.TMultiplexedProtocol(self.bprotocol, "conn_mgr")
    self.conn = conn_mgr_client_module.Client(self.conn_mgr_protocol)
    self.conn_hdl = self.conn.client_init()

    self.mc_protocol = TMultiplexedProtocol.TMultiplexedProtocol(self.bprotocol, "mc")
    self.mc = mc_client_module.Client(self.mc_protocol)
    self.mc_sess_hdl = self.mc.mc_create_session()

    self.dev_tgt = DevTarget_t(0, hex_to_i16(0xFFFF))
    self.dev_tgt0 = DevTarget_t(0, hex_to_i16(0))
    self.dev_tgt1 = DevTarget_t(0, hex_to_i16(1))

    self.flags = eval("self.dp_ttypes."+prog_name+"_register_flags_t(read_hw_sync=True)")

    self.mcGroups = []

    self.prog_name = prog_name

  def enab_ports_sym_bw(self, enab_ports, bw):
    bwconfig = self.bw_dict[bw]
    print("Enable ports: "+str(enab_ports)+" with speed "+bw)
    try:
      for port in enab_ports:
        self.pal.pal_port_add(0, port, bwconfig, pal_fec_type_t.BF_FEC_TYP_NONE)
        self.pal.pal_port_enable(0, port)
      print("Port configuration suceeds")
    except:
      print("Port configuration fails")

  def add_rule_exact_read_action_arg(self, tbl_name, action_name, match_arg, action_arg):
    match_spec = eval("self.dp_ttypes."+self.prog_name+"_"+tbl_name+"_match_spec_t("+str(match_arg)+")")
    action_spec = eval("self.dp_ttypes."+self.prog_name+"_"+action_name+"_action_spec_t("+str(action_arg)+")")
    eval("self.client."+tbl_name+"_table_add_with_"+action_name+"(self.conn_hdl, self.dev_tgt, match_spec, action_spec)")

  def add_rule_exact_read_ternary_read_action_arg(self, tbl_name, action_name, match_arg_exact, match_arg_ternary, match_arg_ternary_mask, priority, action_arg):
    match_spec = eval("self.dp_ttypes."+self.prog_name+"_"+tbl_name+"_match_spec_t("+match_arg_exact+","+match_arg_ternary+","+match_arg_ternary_mask+")")
    action_spec = eval("self.dp_ttypes."+self.prog_name+"_"+action_name+"_action_spec_t("+action_arg+")")
    eval("self.client."+tbl_name+"_table_add_with_"+action_name+"(self.conn_hdl, self.dev_tgt, match_spec, priority, action_spec)")

  def add_rule_exact_read_ternary_read(self, tbl_name, action_name, match_arg_exact, match_arg_ternary, match_arg_ternary_mask, priority):
    match_spec = eval("self.dp_ttypes."+self.prog_name+"_"+tbl_name+"_match_spec_t("+match_arg_exact+","+match_arg_ternary+","+match_arg_ternary_mask+")")
    eval("self.client."+tbl_name+"_table_add_with_"+action_name+"(self.conn_hdl, self.dev_tgt, match_spec, priority)")

  def add_rule_exact_reads_action_arg(self, tbl_name, action_name, match_args, action_arg):
    match_spec_stmt = ("self.dp_ttypes."+self.prog_name+"_"+tbl_name+"_match_spec_t(")
    first = True
    for match_arg in match_args:
      if first:
        match_spec_stmt += match_arg
	first = False
      else:
        match_spec_stmt += (","+match_arg)
    match_spec_stmt += ")"
    match_spec = eval(match_spec_stmt)
    action_spec = eval("self.dp_ttypes."+self.prog_name+"_"+action_name+"_action_spec_t("+action_arg+")")
    eval("self.client."+tbl_name+"_table_add_with_"+action_name+"(self.conn_hdl, self.dev_tgt, match_spec, action_spec)")

  def connect(self):
    match_spec = self.dp_ttypes.prog_ti_ipv4_forwarding_match_spec_t(
      ipv4Addr_to_i32("10.1.1.5"), # dest first
      ipv4Addr_to_i32("255.255.255.255"),
      ipv4Addr_to_i32("10.1.1.3"),
      ipv4Addr_to_i32("0.0.0.0"))
    action_spec = self.dp_ttypes.prog_ai_set_egr_port_action_spec_t(163)
    priority = hex_to_i32(0x2)
    self.client.ti_ipv4_forwarding_table_add_with_ai_set_egr_port(
      self.conn_hdl, self.dev_tgt, match_spec,
      priority, action_spec)

    match_spec = self.dp_ttypes.prog_ti_ipv4_forwarding_match_spec_t(
      ipv4Addr_to_i32("10.1.1.3"),
      ipv4Addr_to_i32("255.255.255.255"),
      ipv4Addr_to_i32("10.1.1.5"),
      ipv4Addr_to_i32("0.0.0.0"))
    # action_spec = self.dp_ttypes.prog_ai_set_egr_port_action_spec_t(hex_to_i16(163)) # 163 0xA3
    action_spec = self.dp_ttypes.prog_ai_set_egr_port_action_spec_t(155)
    priority = hex_to_i32(0x2)
    self.client.ti_ipv4_forwarding_table_add_with_ai_set_egr_port(
      self.conn_hdl, self.dev_tgt, match_spec,
      priority, action_spec)

  def print_pktgen_counter_for_app(self, appid):
    print("App "+str(appid)+":"+str(self.conn.pktgen_get_pkt_counter(self.conn_hdl, self.dev_tgt, appid)))

  def read_reg_element_for_pipe(self, regname, index, pipeid):
    value = eval("self.client.register_read_"+regname+"(self.conn_hdl, self.dev_tgt, "+str(index)+", self.flags)")
    self.conn.complete_operations(self.conn_hdl)
    return value[pipeid]

  def create_mc_grp(self, mc_gid, mc_ports):

    lag_map = set_port_or_lag_bitmap(256, [])
    flood_ports = [int(p) for p in mc_ports]
    print("mc gid: %s; ports: %s"%(mc_gid, str(mc_ports)))
    port_map = set_port_or_lag_bitmap(288, list(flood_ports))
    print(port_map)
  
    mc_grp_hdl = self.mc.mc_mgrp_create(self.mc_sess_hdl, self.dev_tgt.dev_id, hex_to_i16(mc_gid))
    mc_node_hdl = self.mc.mc_node_create(self.mc_sess_hdl, self.dev_tgt.dev_id, 0, port_map, lag_map)
    self.mc.mc_associate_node(self.mc_sess_hdl, self.dev_tgt.dev_id, mc_grp_hdl, mc_node_hdl, 0, 0)
    self.mcGroups.append((mc_node_hdl, mc_grp_hdl))
    # mc.mc_mgrp_destroy(mc_sess_hdl, dev_tgt.dev_id, hex_to_i32(mc_grp_hdl))
    self.conn.complete_operations(self.conn_hdl)
    self.mc.mc_complete_operations(self.mc_sess_hdl)

  def set_default_rule_action_args(self, tbl_name, action_name, action_args):
    action_spec_stmt = "self.dp_ttypes."+self.prog_name+"_"+action_name+"_action_spec_t("
    for arg in action_args:
      action_spec_stmt += str(arg)
    action_spec_stmt += ")"
    action_spec = eval(action_spec_stmt)
    eval("self.client."+tbl_name+"_set_default_action_"+action_name+"(self.conn_hdl, self.dev_tgt, action_spec)")

  def cleanup(self):
    self.mc.mc_destroy_session(self.mc_sess_hdl)
    self.conn.complete_operations(self.conn_hdl)
    self.conn.client_cleanup(self.conn_hdl)
    self.transport.close()


def debug(master=None):
  if master is None: 
    print("PID: " + str(os.getpid()))
    master = Controller("orbweaver")

  print("--- Trigger debug modules to record for 0.1s ---")
  master.set_default_rule_action_args("ti_set_record_", "ai_set_record_", [1])
  master.set_default_rule_action_args("te_set_record_", "ae_set_record_", [1])
  time.sleep(0.1)
  master.set_default_rule_action_args("ti_set_record_", "ai_set_record_", [0])
  master.set_default_rule_action_args("te_set_record_", "ae_set_record_", [0])

  print("pipe0&1 ri_port2ctr_")
  for port in range(256):
    value = master.read_reg_element_for_pipe("ri_port2ctr_", port, pipeid=port_to_pipe(port))
    if value != 0:
      print(port, value)

  print("pipe0&1 re_port2ctr_")
  for port in range(256):
    value = master.read_reg_element_for_pipe("re_port2ctr_", port, pipeid=port_to_pipe(port))
    if value != 0:
      print(port, value)

  print("pipe0 ri_mcgid2ctr_")
  for index in range(2048):
    value = long(master.read_reg_element_for_pipe("ri_mcgid2ctr_", index, pipeid=0))
    if value != 0:
      print(index, value)
  print("pipe1 ri_mcgid2ctr_")
  for index in range(2048):
    value = long(master.read_reg_element_for_pipe("ri_mcgid2ctr_", index, pipeid=1))
    if value != 0:
      print(index, value)

  for appid in [1, 2]:
    master.print_pktgen_counter_for_app(appid)

  # with open(sys.argv[1], "w") as write_file:                                                                                                              
  #     json.dump(index2count_dict, write_file)
  # num_right_shift = 0

  print("pipe0 ri_gap_hist_ (strictly 0 otherwise):")
  print("# gap, count")
  gap2count = {}
  sum_gap = 0.0
  sum_count = 0
  for index in range(131072):
    value = long(master.read_reg_element_for_pipe("ri_gap_hist_", index, pipeid=0))
    if value != 0:
      gap2count[index] = value
    sum_count += value
    sum_gap += (index*value)
  print("Total sample #: {}".format(sum_count))
  if sum_count != 0:
    for index in range(131072):
      if index in gap2count.keys():
        print("{0}[ns], {1}, {2}%".format(index, gap2count[index], 1.0*gap2count[index]/sum_count*100.0))
    print("Mean gap: {0}".format(1.0*sum_gap/sum_count))

  print("pipe0 re_gap_hist_ (strictly 0 otherwise):")
  print("# gap, count")
  gap2count = {}
  sum_gap = 0.0
  sum_count = 0
  for index in range(131072):
    value = long(master.read_reg_element_for_pipe("re_gap_hist_", index, pipeid=0))
    if value != 0:
      gap2count[index] = value
    sum_count += value
    sum_gap += (index*value)
  print("Total sample #: {}".format(sum_count))
  if sum_count != 0:
    for index in range(131072):
      if index in gap2count.keys():
        print("{0}[ns], {1}, {2}%".format(index, gap2count[index], 1.0*gap2count[index]/sum_count*100.0))
    print("Mean gap: {0}".format(1.0*sum_gap/sum_count))
  #interval_ns = index*2**num_right_shift;
  master.cleanup()


def config(w_debug):

  print("PID: " + str(os.getpid()))
  master = Controller("orbweaver")

  mc_pipe0_ports = [0<<7|i for i in range(0, 61, 4)]
  mc_pipe1_ports = [1<<7|i for i in range(0, 61, 4)]

  data = {}
  with open('utils/servers.json', 'r') as f:
    data=json.loads(f.read())
  server_ports = []
  for val in data.values():
    server_ports.append(val['port_id'])

  print("--- Set up ports (physically occupied for successful enabling) ---")
  master.enab_ports_sym_bw(mc_pipe0_ports, "100G")
  master.enab_ports_sym_bw(server_ports, "25G")
 
  print("--- Create MC groups (binning 4 ports as an example) ---")
  mc_pipe0_combinations = [
    [0, 4, 8, 12],
    [16, 20, 24, 28],
    [32, 36, 40, 44],
    [48, 52, 56, 60],
    [0, 4, 8, 12, 16, 20, 24, 28],
    [0, 4, 8, 12, 32, 36, 40, 44],
    [0, 4, 8, 12, 48, 52, 56, 60],
    [16, 20, 24, 28, 32, 36, 40, 44],
    [16, 20, 24, 28, 48, 52, 56, 60],
    [32, 36, 40, 44, 48, 52, 56, 60],
    [0, 4, 8, 12, 16, 20, 24, 28, 32, 36, 40, 44],
    [0, 4, 8, 12, 16, 20, 24, 28, 48, 52, 56, 60],
    [0, 4, 8, 12, 32, 36, 40, 44, 48, 52, 56, 60],
    [16, 20, 24, 28, 32, 36, 40, 44, 48, 52, 56, 60],
    [i for i in range(0, 61, 4)]
  ]
  mc_grp_ids = [i for i in range(201, 216)]
  for i in range(len(mc_grp_ids)):
    master.create_mc_grp(mc_grp_ids[i], mc_pipe0_combinations[i])

  print("--- Configure DP states ---")
  master.add_rule_exact_reads_action_arg(tbl_name="ti_set_pkt_type",
                                        action_name="ai_set_pkt_type",
					match_args=["0x1234", "68"],
					action_arg="0x1")

  for index, port in enumerate(mc_pipe0_ports):
    master.add_rule_exact_reads_action_arg(tbl_name="ti_set_mask",
                                         action_name="ai_set_mask",
					 match_args=["0x0", str(port)],
					 action_arg=str(hex_to_i16(1<<index))
					 )
  master.add_rule_exact_reads_action_arg(tbl_name="ti_set_mask",
                                      action_name="ai_set_mask",
				      match_args=["0x1", "0x0"],
				      action_arg=str(hex_to_i16(0xFFFF)))

  ternary_matches = [
    0x0FFF,
    0xF0FF,
    0xFF0F,
    0xFFF0,
    0x00FF,
    0x0F0F,
    0x0FF0,
    0xF00F,
    0xF0F0,
    0xFF00,
    0x000F,
    0x00F0,
    0x0F00,
    0xF000,
    0x0000
  ]
  ternary_masks = [
    0x0FFF,
    0xF0FF,
    0xFF0F,
    0xFFF0,
    0x00FF,
    0x0F0F,
    0x0FF0,
    0xF00F,
    0xF0F0,
    0xFF00,
    0x000F,
    0x00F0,
    0x0F00,
    0xF000,
    0x0000
  ]
  # Emulate if-else
  priorities = [
    0x2, 0x2, 0x2, 0x2,
    0x3, 0x3, 0x3, 0x3, 0x3, 0x3,
    0x4, 0x4, 0x4, 0x4,
    0x5 
  ]
  master.add_rule_exact_read_ternary_read(tbl_name="ti_mc_seed",
                                        action_name="ai_drop",
					match_arg_exact="68",
					match_arg_ternary=str(hex_to_i16(0xFFFF)),
					match_arg_ternary_mask=str(hex_to_i16(0xFFFF)),
					priority=0x1 # Prioritized for table lookup
					)
  for i in range(len(ternary_matches)):
    master.add_rule_exact_read_ternary_read_action_arg(tbl_name="ti_mc_seed",
                                        action_name="ai_mc_seed",
					match_arg_exact="68",
					match_arg_ternary=str(hex_to_i16(ternary_matches[i])),
					match_arg_ternary_mask=str(hex_to_i16(ternary_masks[i])),
					priority=priorities[i],
					action_arg=str(mc_grp_ids[i]))

  def trigger_debug(signum, stack):
    print('Received signal:', signum)
    debug(master)
  
  if w_debug:
    signal.signal(signal.SIGUSR1, trigger_debug)
    print("Wait for kill -USR1 {}...".format(os.getpid()))
    time.sleep(100000)
  else:
    master.cleanup()


if __name__ == '__main__':

  parser = argparse.ArgumentParser()
  parser.add_argument('-m', '--mode', type=str, required=False, default="config", choices=["config", "debug", "config+debug"], help="Run in mode [config|debug|config+debug]")
  args = parser.parse_args()

  if args.mode == "debug":
    debug()
  elif args.mode == "config":
    config(False)
  elif args.mode == "config+debug":
    config(True)
  else:
    print("ERR")


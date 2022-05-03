import struct

# Third party: https://github.com/p4lang/p4factory/blob/master/testutils/utils.py
# thrift does not support unsigned integers
def hex_to_i16(h):
  x = int(h)
  if (x > 0x7FFF): x-= 0x10000
  return x
def hex_to_i32(h):
  x = int(h)
  if (x > 0x7FFFFFFF): x-= 0x100000000
  return x
def hex_to_byte(h):
  x = int(h)
  if (x > 0x7F): x-= 0x100
  return x
def uint_to_i32(u):
  if (u > 0x7FFFFFFF): u-= 0x100000000
  return u

def bytes_to_string(byte_array):
  form = 'B' * len(byte_array)
  return struct.pack(form, *byte_array)

def string_to_bytes(string):
  form = 'B' * len(string)
  return list(struct.unpack(form, string))

def macAddr_to_string(addr):
  byte_array = [int(b, 16) for b in addr.split(':')]
  return bytes_to_string(byte_array)

def ipv4Addr_to_i32(addr):
  byte_array = [int(b) for b in addr.split('.')]
  res = 0
  for b in byte_array: res = res * 256 + b
  return uint_to_i32(res)

def stringify_macAddr(addr):
  return ':'.join('%02x' % byte_to_u(x) for x in addr)

def i32_to_ipv4Addr(addr):
  return socket.inet_ntoa(struct.pack("!I", addr))

def ipv6Addr_to_string(addr):
  return (str(socket.inet_pton(socket.AF_INET6, addr)))

# Tofino-specific SDE's example helpers related to multicast identifier
def port_to_pipe(port): 
  return port >> 7
def port_to_pipe_local_id(port):
  return port & 0x7F
def port_to_bit_idx(port):
  pipe = port_to_pipe(port)
  index = port_to_pipe_local_id(port)
  return 72 * pipe + index
def set_port_or_lag_bitmap(bit_map_size, indicies):
  bit_map = [0] * ((bit_map_size+7)/8)
  for i in indicies:
    index = port_to_bit_idx(i)
    bit_map[index/8] = (bit_map[index/8] | (1 << (index%8))) & 0xFF
  return bytes_to_string(bit_map)
def to_devport(pipe, port):
  return pipe << 7 | port
def to_pipeport(dp):
  return (dp >> 7, dp & 0x7F)
def devport_to_mcport(dp): 
  (pipe, port) = to_pipeport(dp)
  return pipe * 72 + port
def mcport_to_devport(mcport):
  return to_devport(mcport / 72, mcport % 72)
def devports_to_mcbitmap(devport_list):
  bit_map = [0] * ((288 + 7) / 8)
  for dp in devport_list:
    mc_port = devport_to_mcport(dp)
    bit_map[mc_port / 8] |= (1 << (mc_port % 8))
  return bytes_to_string(bit_map)
def mcbitmap_to_devports(mc_bitmap):
  bit_map = string_to_bytes(mc_bitmap)
  devport_list = []
  for i in range(0, len(bit_map)):
    for j in range(0, 8):
      if bit_map[i] & (1 << j) != 0:
        devport_list.append(mcport_to_devport(i * 8 + j))
  return devport_list
def lags_to_mcbitmap(lag_list):
  bit_map = [0] * ((256 + 7) / 8)
  for lag in lag_list:
    bit_map[lag / 8] |= (1 << (lag % 8))
  return bytes_to_string(bit_map)
def mcbitmap_to_lags(mc_bitmap):
  bit_map = string_to_bytes(mc_bitmap)
  lag_list = []
  for i in range(0, len(bit_map)):
    for j in range(0, 8):
      if bit_map[i] & (1 << j) != 0:
        devport_list.append(i * 8 + j)
  return lag_list

import os
def create_dir(name):
  try:
    os.makedirs(name)
  except OSError as e:
    if e.errno == errno.EEXIST:
      pass
    else:
      raise


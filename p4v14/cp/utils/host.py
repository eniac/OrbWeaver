import argparse
import json
import os
import subprocess
import sys

parser = argparse.ArgumentParser()
parser.add_argument("-a", "--alias", type=str, required=True, 
        choices=["scarlet", "plum", "peacock", "green", "mustard", 'white'], help="Alias for the server")

args = parser.parse_args()

with open('servers.json', 'r') as f:
  servers_json=json.loads(f.read())

server = servers_json[args.alias]

cmds = [
  "ip link",
  "sudo ip link set dev " + server['interface']  + " up",
  "sudo ip addr add " + server['ip_addr']  + "/24 dev " + server['interface'],
  "sudo ip route add 10.1.1.0/24 dev " + server['interface'],
        ]
for alias in servers_json.keys():
  if alias != args.alias:
    cmds.append("sudo arp -s "+servers_json[alias]['ip_addr']+" "+servers_json[alias]['ether_addr'])

for cmd in cmds:
  print(cmd)
  subprocess.call(cmd.split())

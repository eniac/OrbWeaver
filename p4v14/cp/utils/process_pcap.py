import argparse
import subprocess


def info(pcap_name):
  cmd = "capinfos -A " + pcap_name
  subprocess.call(cmd.split())

def replay(pcap_name, interface, loop_num, multiplier):
  # Presume -x, can't coexist with --pps or --mbps speed specifier
  cmd="tcpreplay -i "+interface+" -x "+str(multiplier)+" -T nano -K --preload-pcap -l "+str(loop_num)+" "+pcap_name
  print(cmd)
  subprocess.call(cmd.split())


if __name__ == '__main__':

  parser = argparse.ArgumentParser()
  parser.add_argument("pcap_name", type=str, help="Name of the input pcap file")

  subcmds = parser.add_subparsers(dest="cmd")

  cmd_replay = subcmds.add_parser("replay")
  cmd_replay.add_argument("-i", "--interface", type=str, required=False, default="enp101s0f0", help="Interface name")
  cmd_replay.add_argument("-l", "--loop_num", type=int, required=False, default=1000, help="Number of replicas to replay")
  cmd_replay.add_argument("-x", "--multiplier", type=float, required=False, default=1, help="Replay rate multiplier")

  cmd_info = subcmds.add_parser("info")

  args = parser.parse_args()

  if args.cmd == "replay":
    replay(args.pcap_name, args.interface, args.loop_num, args.multiplier)
  elif args.cmd == "info":
    info(args.pcap_name)
  else:
    print("ERR")

#define UDP_TYPE 0x11
parser start {
  return parse_ethernet;
}
parser parse_ethernet {
  extract(ethernet);
  return select(latest.etherType) {
    0x800 : parse_ipv4;
//        ETHERTYPE_PKTGEN: parse_pktgen;
    default: ingress;
  }
}
parser parse_ipv4 {
  extract(ipv4);
  return select(latest.fragOffset, latest.protocol) {
    UDP_TYPE : parse_udp;
    default: ingress;
  }
}
parser parse_udp {
  extract(udp);
  return ingress;
}

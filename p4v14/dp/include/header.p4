header_type ethernet_t {
  fields {
    dstAddr : 48;  // pktgen header
    srcAddr : 48;
    etherType : 16;
  }
}
header_type ipv4_t {
  fields {
    version : 4;
    ihl : 4;
    diffserv : 8;
    totalLen : 16;
    identification : 16;
    flags : 3;
    fragOffset : 13;
    ttl : 8;
    protocol : 8;
    hdrChecksum : 16;
    srcAddr : 32;
    dstAddr : 32;
  }
}
header_type udp_t {
  fields {
    srcPort : 16;
    dstPort : 16;
    hdr_length : 16;
    checksum : 16;
  }
}
header ethernet_t ethernet;
header ipv4_t ipv4;
header udp_t udp;

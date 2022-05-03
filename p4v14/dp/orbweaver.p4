#include <tofino/intrinsic_metadata.p4>
#include <tofino/constants.p4>
#include <tofino/primitives.p4>
#include <tofino/stateful_alu_blackbox.p4>

#include "include/header.p4"
#include "include/parser.p4"
#include "include/cksum.p4"
#include "include/ci_meas.p4"
#include "include/ce_meas.p4"

#define USER_TYPE 0x0
#define LOCAL_IDLE_TYPE 0x1
#define EXTERNAL_IDLE_TYPE 0x2
#define FILTER_WIDTH 16


header_type ow_metadata_t {
  fields {
    type: 8;
    egr_port: 16;
    mask: FILTER_WIDTH;
    bitmap: FILTER_WIDTH;
  }
}
metadata ow_metadata_t ow_md;

action ai_drop() {
  drop();
}
action ai_nop() {}

action ai_mc_seed(mc_gid) {
  modify_field(ig_intr_md_for_tm.mcast_grp_a, mc_gid);
  modify_field(ig_intr_md_for_tm.qid, 0x7);
}
table ti_mc_seed {
  reads { 
    ig_intr_md.ingress_port: exact;
    ow_md.bitmap: ternary;
  }
  actions {
    ai_mc_seed;
    ai_drop;
  }
  default_action: ai_drop();
}

action ai_forward_user(egress_port){
  add_to_field(ipv4.ttl, -1);
  modify_field(ig_intr_md_for_tm.ucast_egress_port, egress_port);
  // Mirror the egress port to ow_md
  modify_field(ow_md.egr_port, egress_port);
  modify_field(ig_intr_md_for_tm.qid, 0x0);
}
table ti_forward_user {
  reads {
    ipv4.dstAddr : ternary;
  }
  actions {
    ai_forward_user;
    ai_drop;
  }
  default_action: ai_forward_user(0x4);
}

action ai_set_mask(mask) {
  modify_field(ow_md.mask, mask);
}
table ti_set_mask {
  reads { 
    ow_md.type: exact;
    ow_md.egr_port: exact;
  }
  actions { 
    ai_set_mask;
    ai_nop;
  }
  default_action: ai_nop(); 
}

// Record the sending history
register ri_filter {
  width: FILTER_WIDTH;
  instance_count: 1;
}
blackbox stateful_alu bi_filter {
  reg: ri_filter;
  condition_lo: ow_md.type == USER_TYPE;
  update_lo_1_predicate: condition_lo;
  update_lo_1_value: register_lo | ow_md.mask;
  update_lo_2_predicate: not condition_lo;
  update_lo_2_value: register_lo ^ ow_md.mask;

  output_value: register_lo;
  output_dst: ow_md.bitmap;
}
action ai_filter() {
  bi_filter.execute_stateful_alu(0);
}
table ti_filter {
  actions {ai_filter;}
  default_action: ai_filter();
}

action ai_set_pkt_type(type) {
  ow_md.type = type; 
}
table ti_set_pkt_type {
  reads {
    ethernet.etherType: exact;
    ig_intr_md.ingress_port: exact;
  }
  actions { 
    ai_set_pkt_type;
    ai_nop;
    ai_drop;
  }
  default_action: ai_nop();
  size: 256;
}

register ri_mcgid2ctr_ {
  width: 32;
  instance_count: 2048;
}
blackbox stateful_alu bi_mcgid2ctr_ {
  reg: ri_mcgid2ctr_;
  update_lo_1_value: register_lo + 1;
}
action ai_mcgid2ctr_() {
  bi_mcgid2ctr_.execute_stateful_alu(ig_intr_md_for_tm.mcast_grp_a);
}
table ti_mcgid2ctr_ {
  actions {ai_mcgid2ctr_;}
  default_action: ai_mcgid2ctr_();
}

control ingress {
  ci_accounting_();

  apply(ti_set_pkt_type);
  
  if(ow_md.type == USER_TYPE) {
    // Arbitrary user packet forwarding logic
    apply(ti_forward_user);
  } 
  
  apply(ti_set_mask);
  apply(ti_filter);
  
  if(ow_md.type == LOCAL_IDLE_TYPE) {
    apply(ti_mc_seed);
    if(hi_md_.record_ == 0x1) {
      apply(ti_mcgid2ctr_);
    }
  }
}

control egress {
  ce_accounting_();
}

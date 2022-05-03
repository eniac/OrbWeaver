#define EGR_HIST_RANGE 131072
#define EGR_RB_RANGE 131072
#define EGR_MONITORED_PORT 0x4

header_type he_metadata_t_ { 
  fields {
    record_ : 8;
    prev_ts_ : 32; 
    hash_ : 32; 
    diff_ts_ : 32;
    port_local_seq_ : 32;
  }
}
header he_metadata_t_ he_md_;


register re_port2ctr_ {
  width : 32;
  instance_count : 256;
}
blackbox stateful_alu be_port2ctr_ {
  reg : re_port2ctr_;
  update_lo_1_value : register_lo + 1;

  output_value : register_lo;
  output_dst: he_md_.port_local_seq_;
}
action ae_port2ctr_(){
  be_port2ctr_.execute_stateful_alu(eg_intr_md.egress_port);
}
table te_port2ctr_ {
  actions {ae_port2ctr_;}
  default_action: ae_port2ctr_();
}

action ae_set_record_(flag) {
  he_md_.record_ = flag;
}
table te_set_record_ {
  actions {ae_set_record_;}
  default_action: ae_set_record_();
}

register re_prev_ts_ {
  width : 32; 
  instance_count : 1;
}
blackbox stateful_alu be_prev_ts_ {
  reg : re_prev_ts_;
  update_lo_1_value : eg_intr_md_from_parser_aux.egress_global_tstamp;
  output_value : register_lo;
  output_dst : he_md_.prev_ts_;
}
action ae_prev_ts_() {
  be_prev_ts_.execute_stateful_alu(0);
}
@pragma stage 1
table te_prev_ts_ {
  actions {ae_prev_ts_;}
  default_action: ae_prev_ts_();
}

action ae_compute_diff_() {
  he_md_.diff_ts_ = eg_intr_md_from_parser_aux.egress_global_tstamp-he_md_.prev_ts_;
}
@pragma stage 2
table te_compute_diff_ {
  actions {ae_compute_diff_;}
  default_action: ae_compute_diff_();
}

field_list fle_ts_diff_ {
  he_md_.diff_ts_;
}
field_list_calculation flce_ts_diff_hasher_ {
  input {
    fle_ts_diff_;
  }
  algorithm : identity;
  output_width : 32;
}
action ae_compute_hash_(){
  modify_field_with_hash_based_offset(he_md_.hash_, 0, flce_ts_diff_hasher_, EGR_HIST_RANGE);
}
@pragma stage 3
table te_compute_hash_ {
  actions {ae_compute_hash_;}
  default_action: ae_compute_hash_();
}

register re_gap_hist_ {
  width : 32;
  instance_count : EGR_HIST_RANGE;
}
blackbox stateful_alu be_gap_hist_ {
  reg : re_gap_hist_;
  update_lo_1_value : register_lo+1;
}
action ae_gap_hist_(){
  be_gap_hist_.execute_stateful_alu(he_md_.hash_);
}
@pragma stage 4
table te_gap_hist_ {
  actions {ae_gap_hist_;}
  default_action: ae_gap_hist_();
}

register re_gap_rb_ {
  width : 32;
  instance_count : EGR_RB_RANGE;
}
blackbox stateful_alu be_gap_rb_ {
  reg: re_gap_rb_;
  update_lo_1_value: he_md_.diff_ts_;
}
action ae_gap_rb_(){
  be_gap_rb_.execute_stateful_alu(he_md_.port_local_seq_);
}
@pragma stage 5
table te_gap_rb_ {
  actions { ae_gap_rb_; }
  default_action: ae_gap_rb_();
}

control ce_accounting_ {
  apply(te_set_record_);
  // Weaved stream gap hist of a port
  if(he_md_.record_==1) {
    apply(te_port2ctr_);
    if (eg_intr_md.egress_port==EGR_MONITORED_PORT) {
      apply(te_prev_ts_);
      apply(te_compute_diff_);
      apply(te_compute_hash_);
      apply(te_gap_hist_);
      apply(te_gap_rb_);
    }
  }
}

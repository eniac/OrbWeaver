#define ING_HIST_RANGE 131072
#define NUM_RIGHT_SHIFT 0

header_type hi_metadata_t_ {
  fields {
    prev_ts_ : 32;
    hash_ : 32;
    diff_ts_ns_ : 32;
    diff_ts_ : 32;
    record_ : 8;
  }
}
header hi_metadata_t_ hi_md_;

register ri_port2ctr_ {
  width : 32;
  instance_count : 256;
}
blackbox stateful_alu bi_port2ctr_ {
  reg : ri_port2ctr_;
  update_lo_1_value : register_lo + 1;
}
action ai_port2ctr_ (){
  bi_port2ctr_.execute_stateful_alu(ig_intr_md.ingress_port);
}
table ti_port2ctr_ {
  actions {ai_port2ctr_;}
  default_action: ai_port2ctr_();
}

register ri_prev_ts_ {
  width : 32;
  instance_count : 1;
}
blackbox stateful_alu bi_prev_ts_ {
  reg : ri_prev_ts_;
  update_lo_1_value : ig_intr_md.ingress_mac_tstamp;
//    update_lo_1_value : ig_intr_md_from_parser_aux.ingress_global_tstamp;
  output_value : register_lo;
  output_dst : hi_md_.prev_ts_;
}
action ai_prev_ts_(){
  bi_prev_ts_.execute_stateful_alu(0);
}
@pragma stage 1
table ti_prev_ts_ {
  actions {ai_prev_ts_;}
  default_action: ai_prev_ts_();
}

action ai_compute_diff_() {
  hi_md_.diff_ts_ns_ = ig_intr_md.ingress_mac_tstamp-hi_md_.prev_ts_;
}
@pragma stage 2
table ti_compute_diff_ {
  actions {ai_compute_diff_;}
  default_action: ai_compute_diff_();
}

action ai_offset_diff_() {
  shift_right(hi_md_.diff_ts_, hi_md_.diff_ts_ns_, NUM_RIGHT_SHIFT);
}
@pragma stage 3 
table ti_offset_diff_ {
  actions {ai_offset_diff_;}
  default_action: ai_offset_diff_();
}

field_list fli_ts_diff_ {
  hi_md_.diff_ts_;
}
field_list_calculation flci_ts_diff_hasher_ {
  input {
    fli_ts_diff_;
  }
  algorithm : identity;
  output_width : 32;
}
action ai_compute_hash_(){
  modify_field_with_hash_based_offset(hi_md_.hash_, 0, flci_ts_diff_hasher_, ING_HIST_RANGE);
}
@pragma stage 4 
table ti_compute_hash_ {
  actions {ai_compute_hash_;}
  default_action: ai_compute_hash_();
}

register ri_gap_hist_ {
  width : 32;
  instance_count : ING_HIST_RANGE;
}
blackbox stateful_alu bi_gap_hist_ {
  reg : ri_gap_hist_;
  update_lo_1_value : register_lo+1;
}
action ai_gap_hist_(){
  bi_gap_hist_.execute_stateful_alu(hi_md_.hash_);
}
@pragma stage 5 
table ti_gap_hist_ {
  actions {ai_gap_hist_;}
  default_action: ai_gap_hist_();
}

action ai_set_record_(flag) {
  hi_md_.record_ = flag;
}
table ti_set_record_ {
  actions {ai_set_record_;}
  default_action: ai_set_record_();
}

control ci_accounting_ {
  apply(ti_set_record_);
  if(hi_md_.record_ == 1) {
    apply(ti_port2ctr_);
    if(ig_intr_md.ingress_port==68) {
      apply(ti_prev_ts_);
      apply(ti_compute_diff_);
      apply(ti_offset_diff_);
      apply(ti_compute_hash_);
      apply(ti_gap_hist_);
    }
  }
}

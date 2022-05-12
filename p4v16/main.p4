#include <core.p4>
#include <tna.p4>

#define ETHERTYPE_IPV4 0x0800

#define HIST_RANGE 131072
#define HIST_RANGE_POW2 17
#define NUM_RIGHT_SHIFT 0

#define EGR_RB_RANGE 131072
#define EGR_MONITORED_PORT 0x4

#define USER_TYPE 0x0
#define LOCAL_IDLE_TYPE 0x1
#define EXTERNAL_IDLE_TYPE 0x2
#define FILTER_WIDTH 16


/*=============================================
=            Headers and metadata.            =
=============================================*/
typedef bit<48> mac_addr_t;
header ethernet_h {
    mac_addr_t dst_addr;
    mac_addr_t src_addr;
    bit<16> ether_type;
}

typedef bit<32> ipv4_addr_t;
header ipv4_h {
    bit<4> version;
    bit<4> ihl;
    bit<8> tos;
    bit<16> total_len;
    bit<16> identification;
    bit<3> flags;
    bit<13> frag_offset;
    bit<8> ttl;
    bit<8> protocol;
    bit<16> hdr_checksum;
    ipv4_addr_t src_addr;
    ipv4_addr_t dst_addr;
}

header ig_meas_h_ {
    bit<32> prev_ts_;
    bit<32> hash_;
    bit<32> diff_ts_ns_;
    bit<32> diff_ts_;
    bit<8> record_;
}

header eg_meas_h_ {
    bit<8> record_;
    bit<32> prev_ts_;
    bit<32> hash_;
    bit<32> diff_ts_;
    bit<32> port_local_seq_;
}

header ow_h {
    bit<8> type;
    bit<16> egr_port;
    bit<FILTER_WIDTH> mask;
    bit<FILTER_WIDTH> bitmap;
}

struct header_t {
    ethernet_h ethernet;
    ipv4_h ipv4;
}
struct metadata_t {
    ig_meas_h_ hi_md_;
    eg_meas_h_ he_md_;
    ow_h ow_md;
}

/*===============================
=            Parsing            =
===============================*/
parser TofinoIngressParser(
        packet_in pkt,        
        out ingress_intrinsic_metadata_t ig_intr_md,
        out header_t hdr,
        out metadata_t md) {
    state start {
        pkt.extract(ig_intr_md);
        transition select(ig_intr_md.resubmit_flag) {
            1 : parse_resubmit;
            0 : parse_port_metadata;
        }
    }
    state parse_resubmit {
        transition reject;
    }
    state parse_port_metadata {
        pkt.advance(64); // skip this.
        transition accept;
    }
}

parser EthIpIngressParser(packet_in pkt, 
                   inout ingress_intrinsic_metadata_t ig_intr_md,
                   out header_t hdr,
		   out metadata_t md){

    ParserPriority() parser_prio;
    
    state start {
        transition select(ig_intr_md.ingress_port) {
	    68 : parse_seed;
	    default: parse_ethernet;
	}
    }
    state parse_seed {
        parser_prio.set(7);  // High prio
        pkt.extract(hdr.ethernet);
        transition select(hdr.ethernet.ether_type) {
            ETHERTYPE_IPV4 : parse_ip;
            default : accept;
        }
    }
    state parse_ethernet {
        pkt.extract(hdr.ethernet);
        transition select(hdr.ethernet.ether_type) {
            ETHERTYPE_IPV4 : parse_ip;
            default : accept;
        }
    }
    state parse_ip {
        pkt.extract(hdr.ipv4);
        transition accept;
    }
}

parser EthIpEgressParser(packet_in pkt, 
                   out header_t hdr,
		   out metadata_t md){

    state start {
        pkt.extract(hdr.ethernet);
        transition select(hdr.ethernet.ether_type) {
            ETHERTYPE_IPV4 : parse_ip;
            default : accept;
        }
    }
    state parse_ip {
        pkt.extract(hdr.ipv4);
        transition accept;
    }
}

parser TofinoEgressParser(
        packet_in pkt,
        out egress_intrinsic_metadata_t eg_intr_md) {
    state start {
        pkt.extract(eg_intr_md);
        transition accept;
    }
}

/*========================================
=            Ingress parsing             =
========================================*/
parser IngressParser(
        packet_in pkt,
        out header_t hdr, 
        out metadata_t md,
        out ingress_intrinsic_metadata_t ig_intr_md)
{
    state start {
        TofinoIngressParser.apply(pkt, ig_intr_md, hdr, md);
        EthIpIngressParser.apply(pkt, ig_intr_md, hdr, md);
        transition accept;
    }
}


control Ci_accounting_(
        inout ingress_intrinsic_metadata_for_deparser_t ig_dprsr_md,
        in ingress_intrinsic_metadata_t ig_intr_md,
        inout ingress_intrinsic_metadata_for_tm_t ig_tm_md,
        inout metadata_t md,
        in bit<32> computed_var) {
    
    Register<bit<32>, bit<32>>(256, 0) ri_port2ctr_;
    RegisterAction<bit<32>, bit<32>, bit<32>>(ri_port2ctr_) rai_port2ctr_ = {
        void apply(inout bit<32> val) {
	    val = val + 1;
	}
    };
    action ai_port2ctr_() {
        rai_port2ctr_.execute((bit<32>)ig_intr_md.ingress_port);
    }
    table ti_port2ctr_ {
        actions = { ai_port2ctr_; }
	const default_action = ai_port2ctr_();
    }

    Register<bit<32>, bit<32>>(1, 0) ri_prev_ts_;
    RegisterAction<bit<32>, bit<32>, bit<32>>(ri_prev_ts_) rai_prev_ts_ = {
        void apply(inout bit<32> val, out bit<32> ret) {
	    ret = val;
	    val = (bit<32>)ig_intr_md.ingress_mac_tstamp;
	}
    };
    action ai_prev_ts_() {
        md.hi_md_.prev_ts_ = rai_prev_ts_.execute(0);
    }
    table ti_prev_ts_ {
        actions = { ai_prev_ts_; }
	const default_action = ai_prev_ts_();
    }

    action ai_compute_diff_() {
        md.hi_md_.diff_ts_ns_ = (bit<32>)ig_intr_md.ingress_mac_tstamp-md.hi_md_.prev_ts_;
    }
    table ti_compute_diff_ {
        actions = {
	    ai_compute_diff_;
	}
	const default_action = ai_compute_diff_();
    }

    action ai_offset_diff_() {
        md.hi_md_.diff_ts_ = (md.hi_md_.diff_ts_ns_ >> NUM_RIGHT_SHIFT);
    }
    table ti_offset_diff_ {
        actions = { ai_offset_diff_; }
	const default_action = ai_offset_diff_();
    }

    Hash<bit<HIST_RANGE_POW2>>(HashAlgorithm_t.IDENTITY) hashi_ts_diff_;
    action ai_compute_hash_() {
        md.hi_md_.hash_ = (bit<32>)hashi_ts_diff_.get(
	  {md.hi_md_.diff_ts_}
	);
    }
    table ti_compute_hash_ {
        actions = {ai_compute_hash_;}
	default_action = ai_compute_hash_();
    }

    Register<bit<32>, bit<32>>(HIST_RANGE, 0) ri_gap_hist_;
    RegisterAction<bit<32>, bit<32>, bit<32>>(ri_gap_hist_) rai_gap_hist_ = {
        void apply(inout bit<32> val) {
	    val = val + 1;
	}
    };
    action ai_gap_hist_() {
        rai_gap_hist_.execute(md.hi_md_.hash_);
    }
    table ti_gap_hist_ {
        actions = {ai_gap_hist_;}
	default_action = ai_gap_hist_();
    }

    action ai_set_record_(bit<8> flag) {
        md.hi_md_.record_ = flag; 
    }
    table ti_set_record_ {
        actions = {ai_set_record_;}
        default_action = ai_set_record_(0x0);
    }

    apply {
        ti_set_record_.apply();
	if(md.hi_md_.record_ == 1) {
            ti_port2ctr_.apply();
	    if(ig_intr_md.ingress_port==68) { 
	        ti_prev_ts_.apply();
	        ti_compute_diff_.apply();
	        ti_offset_diff_.apply();
	        ti_compute_hash_.apply();
	        ti_gap_hist_.apply();
	    }
        }
    }
}

/*===========================================
=            ingress match-action             =
===========================================*/
control Ingress(
        inout header_t hdr, 
        inout metadata_t md,
        in ingress_intrinsic_metadata_t ig_intr_md,
        in ingress_intrinsic_metadata_from_parser_t ig_prsr_md,
        inout ingress_intrinsic_metadata_for_deparser_t ig_dprsr_md,
        inout ingress_intrinsic_metadata_for_tm_t ig_tm_md) {

    Ci_accounting_() ci_accounting_; 

    action ai_drop() {
        ig_dprsr_md.drop_ctl = 0x1;
    }
    action ai_reflect() {
        ig_tm_md.ucast_egress_port = ig_intr_md.ingress_port;
    }
    action ai_nop() {
    }
   
    action ai_mc_seed(bit<16> mc_gid) {
        ig_tm_md.mcast_grp_a = mc_gid;
	ig_tm_md.qid = 0x7;
    }
    table ti_mc_seed {
        key = {
	    ig_intr_md.ingress_port: exact;
	    md.ow_md.bitmap: ternary;
	}
	actions = {
	    ai_mc_seed;
	    ai_drop;
	}
	default_action = ai_drop();
    }

    action ai_forward_user(bit<9> egress_port){
        ig_tm_md.ucast_egress_port = egress_port;
	// Mirror the egress port to ow_md
	md.ow_md.egr_port = (bit<16>)egress_port;
	ig_tm_md.qid = 0x0;
    }
    table ti_forward_user {
        key = {
	    hdr.ipv4.dst_addr : ternary;
	}
	actions = {
	    ai_forward_user;
	    ai_drop;
	}
	default_action = ai_forward_user(0x4);
    }

    table ti_process_upstream_idle {
        actions = { ai_drop; }
        default_action = ai_drop();
    }

    action ai_set_mask(bit<FILTER_WIDTH> mask) {
        md.ow_md.mask = mask;
    }
    table ti_set_mask {
        key = {
	    md.ow_md.type: exact;
	    md.ow_md.egr_port: exact;
	}
	actions = {
	    ai_set_mask;
	    ai_nop;
	}
	default_action = ai_nop();
    }

    // Record the sending history
    Register<bit<FILTER_WIDTH>, bit<32>>(1, 0) ri_filter;
    RegisterAction<bit<FILTER_WIDTH>, bit<32>, bit<FILTER_WIDTH>>(ri_filter) rai_filter = {
        void apply(inout bit<FILTER_WIDTH> val, out bit<FILTER_WIDTH> ret) {
	    ret = val;
            if (md.ow_md.type == USER_TYPE) {
	        val = val | md.ow_md.mask;
	    } else {
	        val = val ^ md.ow_md.mask;
	    }
	}
    };
    action ai_filter() {
        md.ow_md.bitmap = rai_filter.execute(0);
    }
    table ti_filter {
        actions = {ai_filter;}
	const default_action = ai_filter();
    }

    action ai_set_pkt_type(bit<8> type) {
        md.ow_md.type = type;
    }
    table ti_set_pkt_type {
        key = {
	    hdr.ethernet.ether_type: exact;
	    ig_intr_md.ingress_port: exact;
	}
	actions = {
	    ai_set_pkt_type;
	}
	default_action = ai_set_pkt_type(USER_TYPE);
    }

    Register<bit<32>, bit<32>>(2048, 0) ri_mcgid2ctr_;
    RegisterAction<bit<32>, bit<32>, bit<32>>(ri_mcgid2ctr_) rai_mcgid2ctr_ = {
        void apply(inout bit<32> val) {
	    val = val + 1; 
	}
    };
    action ai_mcgid2ctr_() {
        rai_mcgid2ctr_.execute((bit<32>)ig_tm_md.mcast_grp_a);
    }
    table ti_mcgid2ctr_ {
        actions = {ai_mcgid2ctr_;}
	const default_action = ai_mcgid2ctr_();
    }

    apply {
        ci_accounting_.apply(ig_dprsr_md, ig_intr_md, ig_tm_md, md, 0x0);

        ti_set_pkt_type.apply();

        // Custom upstream weaved stream processing

	if(md.ow_md.type == USER_TYPE) {
            // Custom user packet forwarding logic
	    ti_forward_user.apply();
	} else if(md.ow_md.type == EXTERNAL_IDLE_TYPE) {
            // Custom processing of upstream IDLE packets
	    ti_process_upstream_idle.apply();
	} else if(md.ow_md.type == LOCAL_IDLE_TYPE) {
	    // Custom seed packet processing
	}

	ti_set_mask.apply();
	ti_filter.apply();
        
	if(md.ow_md.type == LOCAL_IDLE_TYPE) {
	    // Transform SEED to IDLE
            ti_mc_seed.apply();
	    if(md.hi_md_.record_ == 0x1) {
	        ti_mcgid2ctr_.apply();
	    }
	}
    }
}

control IngressDeparser(
        packet_out pkt, 
        inout header_t hdr, 
        in metadata_t md,
        in ingress_intrinsic_metadata_for_deparser_t ig_dprsr_md) {
    apply {
        pkt.emit(hdr);
    }
}

/*======================================
=            Egress parsing            =
======================================*/
parser EgressParser(
        packet_in pkt,
        out header_t hdr, 
        out metadata_t eg_md,
        out egress_intrinsic_metadata_t eg_intr_md) {
    TofinoEgressParser() tofino_parser;
    EthIpEgressParser() eth_ip_parser; 
    state start {
        tofino_parser.apply(pkt, eg_intr_md);
        transition parse_packet;
    }
    state parse_packet {
        eth_ip_parser.apply(pkt, hdr, eg_md);
        transition accept;        
    }
}

/*=========================================
=            Egress match-action            =
=========================================*/
control Ce_accounting_(
        inout header_t hdr, 
        inout metadata_t eg_md,
        in egress_intrinsic_metadata_t eg_intr_md,
        in egress_intrinsic_metadata_from_parser_t eg_prsr_md,
        inout egress_intrinsic_metadata_for_deparser_t eg_dprsr_md,
        inout egress_intrinsic_metadata_for_output_port_t eg_oport_md){

    Register<bit<32>, bit<32>>(256, 0) re_port2ctr_;
    RegisterAction<bit<32>, bit<32>, bit<32>>(re_port2ctr_) rae_port2ctr_ = {
        void apply(inout bit<32> val, out bit<32> ret) {
	    ret = val; 
	    val = val + 1;
	}
    };
    action ae_port2ctr_() {
        eg_md.he_md_.port_local_seq_ = rae_port2ctr_.execute((bit<32>)eg_intr_md.egress_port);
    }
    table te_port2ctr_ {
        actions = { ae_port2ctr_; }
	const default_action = ae_port2ctr_();
    }

    Register<bit<32>, bit<32>>(1, 0) re_prev_ts_;
    RegisterAction<bit<32>, bit<32>, bit<32>>(re_prev_ts_) rae_prev_ts_ = {
        void apply(inout bit<32> val, out bit<32> ret) {
	    ret = val;
	    val = (bit<32>)eg_prsr_md.global_tstamp;
	}
    };
    action ae_prev_ts_() {
        eg_md.he_md_.prev_ts_ = rae_prev_ts_.execute(0);
    }
    table te_prev_ts_ {
        actions = { ae_prev_ts_; }
	const default_action = ae_prev_ts_();
    }

    action ae_compute_diff_() {
        eg_md.he_md_.diff_ts_ = (bit<32>)eg_prsr_md.global_tstamp - eg_md.he_md_.prev_ts_;
    }
    table te_compute_diff_ {
        actions = {
	    ae_compute_diff_;
	}
	const default_action = ae_compute_diff_();
    }

    Hash<bit<HIST_RANGE_POW2>>(HashAlgorithm_t.IDENTITY) hashe_ts_diff_;
    action ae_compute_hash_() {
        eg_md.he_md_.hash_ = (bit<32>)hashe_ts_diff_.get(
	  {eg_md.he_md_.diff_ts_}
	);
    }
    table te_compute_hash_ {
        actions = {ae_compute_hash_;}
	default_action = ae_compute_hash_();
    }

    Register<bit<32>, bit<32>>(HIST_RANGE, 0) re_gap_hist_;
    RegisterAction<bit<32>, bit<32>, bit<32>>(re_gap_hist_) rae_gap_hist_ = {
        void apply(inout bit<32> val) {
	    val = val + 1;
	}
    };
    action ae_gap_hist_() {
        rae_gap_hist_.execute(eg_md.he_md_.hash_);
    }
    table te_gap_hist_ {
        actions = {ae_gap_hist_;}
	default_action = ae_gap_hist_();
    }

    action ae_set_record_(bit<8> flag) {
        eg_md.he_md_.record_ = flag; 
    }
    table te_set_record_ {
        actions = {ae_set_record_;}
        default_action = ae_set_record_(0x0);
    }

    Register<bit<32>, bit<32>>(EGR_RB_RANGE, 0) re_gap_rb_;
    RegisterAction<bit<32>, bit<32>, bit<32>>(re_gap_rb_) rae_gap_rb_ = {
        void apply(inout bit<32> val) {
	    val = eg_md.he_md_.diff_ts_;
	}
    };
    action ae_gap_rb_() {
        rae_gap_rb_.execute(eg_md.he_md_.port_local_seq_);
    }
    table te_gap_rb_ {
        actions = {ae_gap_rb_;}
	default_action = ae_gap_rb_();
    }

    apply { 
        te_set_record_.apply();
	if(eg_md.he_md_.record_==1) {
            te_port2ctr_.apply();
	    if (eg_intr_md.egress_port==EGR_MONITORED_PORT) {
                te_prev_ts_.apply();
		te_compute_diff_.apply();
		te_compute_hash_.apply();
		te_gap_hist_.apply();
		te_gap_rb_.apply();
	    }
	}
    }
}


control Egress(
        inout header_t hdr, 
        inout metadata_t eg_md,
        in egress_intrinsic_metadata_t eg_intr_md,
        in egress_intrinsic_metadata_from_parser_t eg_prsr_md,
        inout egress_intrinsic_metadata_for_deparser_t eg_dprsr_md,
        inout egress_intrinsic_metadata_for_output_port_t eg_oport_md){

    Ce_accounting_() ce_accounting_; 

    apply { 
        ce_accounting_.apply(hdr, eg_md, eg_intr_md, eg_prsr_md, eg_dprsr_md, eg_oport_md);
	if (eg_md.ow_md.type == LOCAL_IDLE_TYPE) {
            // Custom IDLE packet processing	
	}
    }
}

control EgressDeparser(
        packet_out pkt,
        inout header_t hdr, 
        in metadata_t eg_md,
        in egress_intrinsic_metadata_for_deparser_t eg_dprsr_md) {
    apply {
        pkt.emit(hdr);
    }
}
/*==============================================
=            The switch's pipeline             =
==============================================*/
Pipeline(
    IngressParser(), Ingress(), IngressDeparser(),
    EgressParser(), Egress(), EgressDeparser()) pipe;

Switch(pipe) main;

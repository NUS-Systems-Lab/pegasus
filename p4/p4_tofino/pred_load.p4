#include <tofino/intrinsic_metadata.p4>
#include "tofino/stateful_alu_blackbox.p4"
#include <tofino/constants.p4>

/*************************************************************************
*********************** H E A D E R S  ***********************************
*************************************************************************/

#define ETHERTYPE_IPV4  0x800
#define PROTO_UDP       0x11

#define PEGASUS_ID      0x5047

#define OP_GET          0x0
#define OP_PUT          0x1
#define OP_DEL          0x2
#define OP_REP_R        0x3
#define OP_REP_W        0x4
#define OP_MGR          0x5
#define OP_MGR_REQ      0x6
#define OP_MGR_ACK      0x7
#define OP_DEC          0xF

#define MAX_QUEUE_LEN   0x7FFF
#define RNODE_NONE      0x7F
#define RKEY_NONE       0x7F
#define MAX_RKEY_RATE   0x7FFF

#define OVERLOAD        0xA
#define NNODES          32
#define MAX_REPLICAS    16

header_type ethernet_t {
    fields {
        dstAddr : 48;
        srcAddr : 48;
        etherType : 16;
    }
}

header ethernet_t ethernet;

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

header ipv4_t ipv4;

header_type udp_t {
    fields {
        srcPort : 16;
        dstPort : 16;
        len : 16;
        checksum : 16;
    }
}

header udp_t udp;

header_type apphdr_t {
    fields {
        id : 16;
    }
}

header apphdr_t apphdr;

header_type pegasus_t {
    fields {
        op : 8;
        keyhash : 32;
        node : 8;
        load : 16;
        ver : 32;
        debug_node : 8;
        debug_load : 16;
    }
}

header pegasus_t pegasus;

header_type metadata_t {
    fields {
        rkey_size : 8;
        rset_size : 8;
        rkey_index : 8;
        rset_num_ack : 8;
        probe_rkey_index : 8;
        probe_rset_index : 8;
        node : 8;
        load : 16;
        overload : 1;
        ver_matched : 1;
        read_heavy : 1;
    }
}

metadata metadata_t meta;

/*************************************************************************
*********************** STATEFUL MEMORY  *********************************
*************************************************************************/

/*
   Current number of outstanding requests (queue length)
   at each node
 */
register reg_queue_len {
    width: 16;
    instance_count: 32;
}
/*
   Global least loaded node
 */
register reg_min_node {
    width: 64;
    instance_count: 1;
}
/*
   Least loaded node for each rkey
 */
register reg_rkey_min_node {
    width: 64;
    instance_count: 32;
}
/*
   rkey version number
*/
register reg_rkey_ver_next {
    width: 32;
    instance_count: 32;
}
register reg_rkey_ver_curr {
    width: 32;
    instance_count: 32;
}
/*
   rkey access rate counter
 */
register reg_rkey_rate_counter {
    width: 16;
    instance_count: 32;
}
/*
   rkey replication set
 */
register reg_rkey_size {
    width: 8;
    instance_count: 1;
}
register reg_rset_num_ack {
    width: 8;
    instance_count: 32;
}
register reg_rset_size {
    width: 8;
    instance_count: 32;
}
register reg_rset_1 {
    width: 8;
    instance_count: 32;
}
register reg_rset_2 {
    width: 8;
    instance_count: 32;
}
register reg_rset_3 {
    width: 8;
    instance_count: 32;
}
register reg_rset_4 {
    width: 8;
    instance_count: 32;
}
register reg_rset_5 {
    width: 8;
    instance_count: 32;
}
register reg_rset_6 {
    width: 8;
    instance_count: 32;
}
register reg_rset_7 {
    width: 8;
    instance_count: 32;
}
register reg_rset_8 {
    width: 8;
    instance_count: 32;
}
register reg_rset_9 {
    width: 8;
    instance_count: 32;
}
register reg_rset_10 {
    width: 8;
    instance_count: 32;
}
register reg_rset_11 {
    width: 8;
    instance_count: 32;
}
register reg_rset_12 {
    width: 8;
    instance_count: 32;
}
register reg_rset_13 {
    width: 8;
    instance_count: 32;
}
register reg_rset_14 {
    width: 8;
    instance_count: 32;
}
register reg_rset_15 {
    width: 8;
    instance_count: 32;
}
register reg_rset_16 {
    width: 8;
    instance_count: 32;
}
/*
   Probe rkey counter
*/
register reg_probe_rkey_counter {
    width: 8;
    instance_count: 1;
}
/*
   Probe rset counter
 */
register reg_probe_rset_counter {
    width: 8;
    instance_count: 32;
}
/*
   Read/Write ratio counter
 */
register reg_rkey_read_counter {
    width: 16;
    instance_count: 32;
}
register reg_rkey_write_counter {
    width: 16;
    instance_count: 32;
}
/*************************************************************************
*********************** RESUBMIT  ****************************************
*************************************************************************/
field_list resubmit_fields {
    meta.rkey_index;
    meta.probe_rkey_index;
    meta.node;
    meta.load;
}
/*************************************************************************
*********************** CHECKSUM *****************************************
*************************************************************************/

field_list ipv4_field_list {
    ipv4.version;
    ipv4.ihl;
    ipv4.diffserv;
    ipv4.totalLen;
    ipv4.identification;
    ipv4.flags;
    ipv4.fragOffset;
    ipv4.ttl;
    ipv4.protocol;
    ipv4.srcAddr;
    ipv4.dstAddr;
}

field_list_calculation ipv4_chksum_calc {
    input {
        ipv4_field_list;
    }
    algorithm : csum16;
    output_width: 16;
}

calculated_field ipv4.hdrChecksum {
    update ipv4_chksum_calc;
}

/*************************************************************************
*********************** P A R S E R S  ***********************************
*************************************************************************/

parser start {
    return parse_ethernet;
}

parser parse_ethernet {
    extract(ethernet);
    return select(latest.etherType) {
        ETHERTYPE_IPV4: parse_ipv4;
        default: ingress;
    }
}

parser parse_ipv4 {
    extract(ipv4);
    return select(latest.protocol) {
        PROTO_UDP: parse_udp;
        default: ingress;
    }
}

parser parse_udp {
    extract(udp);
    return parse_apphdr;
}

parser parse_apphdr {
    extract(apphdr);
    return select(latest.id) {
        PEGASUS_ID: parse_pegasus;
        default: ingress;
    }
}

parser parse_pegasus {
    extract(pegasus);
    return ingress;
}

/*************************************************************************
**************  I N G R E S S   P R O C E S S I N G   *******************
*************************************************************************/

/*
   L2 forward
*/
action nop() {
}

action _drop() {
    drop();
}

action l2_forward(port) {
    modify_field(ig_intr_md_for_tm.ucast_egress_port, port);
}

table tab_l2_forward {
    reads {
        ethernet.dstAddr: exact;
    }
    actions {
        l2_forward;
        _drop;
    }
    size: 1024;
}

/*
   node forward
*/
action node_forward(mac_addr, ip_addr, udp_addr, port) {
    modify_field(ethernet.dstAddr, mac_addr);
    modify_field(ipv4.dstAddr, ip_addr);
    modify_field(udp.dstPort, udp_addr);
    modify_field(ig_intr_md_for_tm.ucast_egress_port, port);
}

table tab_node_forward {
    reads {
        meta.node: exact;
    }
    actions {
        node_forward;
        _drop;
    }
    size: 1024;
}

/*
   drop
 */
action do_drop() {
    _drop();
}

table tab_do_drop {
    actions {
        do_drop;
    }
    default_action: do_drop;
    size: 1;
}

/*
   resubmit
 */
action do_resubmit() {
    resubmit(resubmit_fields);
}

table tab_do_resubmit {
    actions {
        do_resubmit;
    }
    default_action: do_resubmit;
    size: 1;
}

/*
   replicated keys
*/
action lookup_rkey(rkey_index) {
    modify_field(meta.rkey_index, rkey_index);
}

action set_default_dst_node() {
    bit_and(meta.node, pegasus.keyhash, 3);
    modify_field(meta.rkey_index, RKEY_NONE);
}

@pragma stage 0
table tab_replicated_keys {
    reads {
        pegasus.keyhash: exact;
    }
    actions {
        lookup_rkey;
        set_default_dst_node;
    }
    default_action: set_default_dst_node;
    size: 32;
}

/*
   inc rkey rate counter
 */
blackbox stateful_alu sa_inc_rkey_rate_counter {
    reg: reg_rkey_rate_counter;
    condition_lo: register_lo < MAX_RKEY_RATE;
    update_lo_1_predicate: condition_lo;
    update_lo_1_value: register_lo + 1;
}
action inc_rkey_rate_counter() {
    sa_inc_rkey_rate_counter.execute_stateful_alu(meta.rkey_index);
}
@pragma stage 1
table tab_inc_rkey_rate_counter {
    actions {
        inc_rkey_rate_counter;
    }
    default_action: inc_rkey_rate_counter;
    size: 1;
}

/*
   rkey version number
 */
blackbox stateful_alu sa_get_rkey_ver_next {
    reg: reg_rkey_ver_next;
    update_lo_1_value: register_lo + 1;
    output_value: alu_lo;
    output_dst: pegasus.ver;
}
blackbox stateful_alu sa_get_rkey_ver_curr {
    reg: reg_rkey_ver_curr;
    output_value: register_lo;
    output_dst: pegasus.ver;
}
blackbox stateful_alu sa_compare_rkey_ver_curr {
    reg: reg_rkey_ver_curr;
    condition_lo: pegasus.ver == register_lo;
    output_predicate: condition_lo;
    output_value: combined_predicate;
    output_dst: meta.ver_matched;
}
blackbox stateful_alu sa_set_rkey_ver_curr {
    reg: reg_rkey_ver_curr;
    condition_lo: pegasus.ver > register_lo;
    update_lo_1_predicate: condition_lo;
    update_lo_1_value: pegasus.ver;
    output_predicate: condition_lo;
    output_value: combined_predicate;
    output_dst: meta.ver_matched;
}

action get_rkey_ver_next() {
    sa_get_rkey_ver_next.execute_stateful_alu(meta.rkey_index);
}
action get_rkey_ver_curr() {
    sa_get_rkey_ver_curr.execute_stateful_alu(meta.rkey_index);
}
action compare_rkey_ver_curr() {
    sa_compare_rkey_ver_curr.execute_stateful_alu(meta.rkey_index);
}
action set_rkey_ver_curr() {
    sa_set_rkey_ver_curr.execute_stateful_alu(meta.rkey_index);
}

@pragma stage 1
table tab_get_rkey_ver_next {
    actions {
        get_rkey_ver_next;
    }
    default_action: get_rkey_ver_next;
    size: 1;
}
@pragma stage 1
table tab_get_rkey_ver_curr {
    actions {
        get_rkey_ver_curr;
    }
    default_action: get_rkey_ver_curr;
    size: 1;
}
@pragma stage 1
table tab_compare_rkey_ver_curr_a {
    actions {
        compare_rkey_ver_curr;
    }
    default_action: compare_rkey_ver_curr;
    size: 1;
}
@pragma stage 1
table tab_compare_rkey_ver_curr_b {
    actions {
        compare_rkey_ver_curr;
    }
    default_action: compare_rkey_ver_curr;
    size: 1;
}
@pragma stage 1
table tab_set_rkey_ver_curr_a {
    actions {
        set_rkey_ver_curr;
    }
    default_action: set_rkey_ver_curr;
    size: 1;
}
@pragma stage 1
table tab_set_rkey_ver_curr_b {
    actions {
        set_rkey_ver_curr;
    }
    default_action: set_rkey_ver_curr;
    size: 1;
}

/*
   get/inc/dec queue len
 */
blackbox stateful_alu sa_get_queue_len {
    reg: reg_queue_len;
    output_value: register_lo;
    output_dst: meta.load;
}
blackbox stateful_alu sa_inc_queue_len {
    reg: reg_queue_len;
    condition_lo: register_lo < MAX_QUEUE_LEN;
    update_lo_1_predicate: condition_lo;
    update_lo_1_value: register_lo + 1;
    output_value: register_lo;
    output_dst: meta.load;
}
blackbox stateful_alu sa_dec_queue_len {
    reg: reg_queue_len;
    condition_lo: register_lo > meta.load;
    update_lo_1_predicate: condition_lo;
    update_lo_1_value: register_lo - meta.load;
    update_lo_2_predicate: not condition_lo;
    update_lo_2_value: 0;
}

action get_queue_len() {
    sa_get_queue_len.execute_stateful_alu(meta.node);
}
action inc_queue_len() {
    sa_inc_queue_len.execute_stateful_alu(meta.node);
}
action dec_queue_len() {
    sa_dec_queue_len.execute_stateful_alu(meta.node);
    add(meta.node, meta.node, 1);
}

@pragma stage 8
table tab_get_queue_len {
    actions {
        get_queue_len;
    }
    default_action: get_queue_len;
    size: 1;
}
@pragma stage 8
table tab_inc_queue_len {
    actions {
        inc_queue_len;
    }
    default_action: inc_queue_len;
    size: 1;
}
@pragma stage 8
table tab_dec_queue_len_a {
    actions {
        dec_queue_len;
    }
    default_action: dec_queue_len;
    size: 1;
}
@pragma stage 8
table tab_dec_queue_len_b {
    actions {
        dec_queue_len;
    }
    default_action: dec_queue_len;
    size: 1;
}

/*
   dummies
 */
blackbox stateful_alu sa_dummy {
    reg: reg_rkey_ver_curr;
}

action dummy() {
    sa_dummy.execute_stateful_alu(0);
}

@pragma stage 1
table tab_dummy {
    actions {
        dummy;
    }
    default_action: dummy;
    size: 1;
}

/*
   get/set/compare min node
 */
blackbox stateful_alu sa_get_min_node {
    reg: reg_min_node;
    output_value: register_hi;
    output_dst: meta.node;
}
blackbox stateful_alu sa_compare_min_node {
    reg: reg_min_node;
    condition_lo: meta.load < register_lo;
    condition_hi: meta.node == register_hi;
    update_lo_1_predicate: condition_lo or condition_hi;
    update_lo_1_value: meta.load;
    update_hi_1_predicate: condition_lo;
    update_hi_1_value: meta.node;
    output_value: register_hi;
    output_dst: pegasus.node; // for MGR
}

action get_min_node() {
    sa_get_min_node.execute_stateful_alu(0);
}
action compare_min_node() {
    sa_compare_min_node.execute_stateful_alu(0);
}

@pragma stage 3
table tab_get_min_node_a {
    actions {
        get_min_node;
    }
    default_action: get_min_node;
    size: 1;
}
@pragma stage 3
table tab_get_min_node_b {
    actions {
        get_min_node;
    }
    default_action: get_min_node;
    size: 1;
}
@pragma stage 3
table tab_compare_min_node {
    actions {
        compare_min_node;
    }
    default_action: compare_min_node;
    size: 1;
}

/*
   get/set rkey min node
 */
blackbox stateful_alu sa_get_rkey_min_node {
    reg: reg_rkey_min_node;
    output_value: register_hi;
    output_dst: meta.node;
}
blackbox stateful_alu sa_set_rkey_min_node {
    reg: reg_rkey_min_node;
     // okay to set 0...will be updated by subsequent packets
    update_lo_1_value: 0;
    update_hi_1_value: meta.node;
}
blackbox stateful_alu sa_compare_rkey_min_node {
    reg: reg_rkey_min_node;
    condition_lo: meta.load < register_lo;
    condition_hi: meta.node == register_hi;
    update_lo_1_predicate: condition_lo or condition_hi;
    update_lo_1_value: meta.load;
    update_hi_1_predicate: condition_lo or condition_hi;
    update_hi_1_value: meta.node;
}
blackbox stateful_alu sa_check_overload_rkey_min_node {
    reg: reg_rkey_min_node;
    condition_lo: meta.load > OVERLOAD;
    condition_hi: meta.node == register_hi;
    update_lo_1_predicate: condition_hi;
    update_lo_1_value: meta.load;
    output_predicate: condition_lo and condition_hi;
    output_value: combined_predicate;
    output_dst: meta.overload;
}

action get_rkey_min_node() {
    sa_get_rkey_min_node.execute_stateful_alu(meta.rkey_index);
}
action set_rkey_min_node() {
    sa_set_rkey_min_node.execute_stateful_alu(meta.rkey_index);
}
action compare_rkey_min_node() {
    sa_compare_rkey_min_node.execute_stateful_alu(meta.probe_rkey_index);
}
action check_overload_rkey_min_node() {
    sa_check_overload_rkey_min_node.execute_stateful_alu(meta.rkey_index);
}

@pragma stage 3
table tab_get_rkey_min_node {
    actions {
        get_rkey_min_node;
    }
    default_action: get_rkey_min_node;
    size: 1;
}
@pragma stage 3
table tab_set_rkey_min_node_a {
    actions {
        set_rkey_min_node;
    }
    default_action: set_rkey_min_node;
    size: 1;
}
@pragma stage 3
table tab_set_rkey_min_node_b {
    actions {
        set_rkey_min_node;
    }
    default_action: set_rkey_min_node;
    size: 1;
}
@pragma stage 3
table tab_compare_rkey_min_node {
    actions {
        compare_rkey_min_node;
    }
    default_action: compare_rkey_min_node;
    size: 1;
}
@pragma stage 3
table tab_check_overload_rkey_min_node {
    actions {
        check_overload_rkey_min_node;
    }
    default_action: check_overload_rkey_min_node;
    size: 1;
}

/*
   get/set rset (1-4)
*/
blackbox stateful_alu sa_get_rset_1 {
    reg: reg_rset_1;
    output_value: register_lo;
    output_dst: meta.node;
}
blackbox stateful_alu sa_set_rset_1 {
    reg: reg_rset_1;
    update_lo_1_value: meta.node;
}
blackbox stateful_alu sa_get_rset_2 {
    reg: reg_rset_2;
    output_value: register_lo;
    output_dst: meta.node;
}
blackbox stateful_alu sa_install_rset_2 {
    reg: reg_rset_2;
    update_lo_1_value: meta.node;
}
blackbox stateful_alu sa_get_rset_3 {
    reg: reg_rset_3;
    output_value: register_lo;
    output_dst: meta.node;
}
blackbox stateful_alu sa_install_rset_3 {
    reg: reg_rset_3;
    update_lo_1_value: meta.node;
}
blackbox stateful_alu sa_get_rset_4 {
    reg: reg_rset_4;
    output_value: register_lo;
    output_dst: meta.node;
}
blackbox stateful_alu sa_install_rset_4 {
    reg: reg_rset_4;
    update_lo_1_value: meta.node;
}
blackbox stateful_alu sa_get_rset_5 {
    reg: reg_rset_5;
    output_value: register_lo;
    output_dst: meta.node;
}
blackbox stateful_alu sa_install_rset_5 {
    reg: reg_rset_5;
    update_lo_1_value: meta.node;
}
blackbox stateful_alu sa_get_rset_6 {
    reg: reg_rset_6;
    output_value: register_lo;
    output_dst: meta.node;
}
blackbox stateful_alu sa_install_rset_6 {
    reg: reg_rset_6;
    update_lo_1_value: meta.node;
}
blackbox stateful_alu sa_get_rset_7 {
    reg: reg_rset_7;
    output_value: register_lo;
    output_dst: meta.node;
}
blackbox stateful_alu sa_install_rset_7 {
    reg: reg_rset_7;
    update_lo_1_value: meta.node;
}
blackbox stateful_alu sa_get_rset_8 {
    reg: reg_rset_8;
    output_value: register_lo;
    output_dst: meta.node;
}
blackbox stateful_alu sa_install_rset_8 {
    reg: reg_rset_8;
    update_lo_1_value: meta.node;
}
blackbox stateful_alu sa_get_rset_9 {
    reg: reg_rset_9;
    output_value: register_lo;
    output_dst: meta.node;
}
blackbox stateful_alu sa_install_rset_9 {
    reg: reg_rset_9;
    update_lo_1_value: meta.node;
}
blackbox stateful_alu sa_get_rset_10 {
    reg: reg_rset_10;
    output_value: register_lo;
    output_dst: meta.node;
}
blackbox stateful_alu sa_install_rset_10 {
    reg: reg_rset_10;
    update_lo_1_value: meta.node;
}
blackbox stateful_alu sa_get_rset_11 {
    reg: reg_rset_11;
    output_value: register_lo;
    output_dst: meta.node;
}
blackbox stateful_alu sa_install_rset_11 {
    reg: reg_rset_11;
    update_lo_1_value: meta.node;
}
blackbox stateful_alu sa_get_rset_12 {
    reg: reg_rset_12;
    output_value: register_lo;
    output_dst: meta.node;
}
blackbox stateful_alu sa_install_rset_12 {
    reg: reg_rset_12;
    update_lo_1_value: meta.node;
}
blackbox stateful_alu sa_get_rset_13 {
    reg: reg_rset_13;
    output_value: register_lo;
    output_dst: meta.node;
}
blackbox stateful_alu sa_install_rset_13 {
    reg: reg_rset_13;
    update_lo_1_value: meta.node;
}
blackbox stateful_alu sa_get_rset_14 {
    reg: reg_rset_14;
    output_value: register_lo;
    output_dst: meta.node;
}
blackbox stateful_alu sa_install_rset_14 {
    reg: reg_rset_14;
    update_lo_1_value: meta.node;
}
blackbox stateful_alu sa_get_rset_15 {
    reg: reg_rset_15;
    output_value: register_lo;
    output_dst: meta.node;
}
blackbox stateful_alu sa_install_rset_15 {
    reg: reg_rset_15;
    update_lo_1_value: meta.node;
}
blackbox stateful_alu sa_get_rset_16 {
    reg: reg_rset_16;
    output_value: register_lo;
    output_dst: meta.node;
}
blackbox stateful_alu sa_install_rset_16 {
    reg: reg_rset_16;
    update_lo_1_value: meta.node;
}

action get_rset_1() {
    sa_get_rset_1.execute_stateful_alu(meta.probe_rkey_index);
}
action set_rset_1() {
    sa_set_rset_1.execute_stateful_alu(meta.rkey_index);
}
action get_rset_2() {
    sa_get_rset_2.execute_stateful_alu(meta.probe_rkey_index);
}
action install_rset_2() {
    sa_install_rset_2.execute_stateful_alu(meta.rkey_index);
}
action get_rset_3() {
    sa_get_rset_3.execute_stateful_alu(meta.probe_rkey_index);
}
action install_rset_3() {
    sa_install_rset_3.execute_stateful_alu(meta.rkey_index);
}
action get_rset_4() {
    sa_get_rset_4.execute_stateful_alu(meta.probe_rkey_index);
}
action install_rset_4() {
    sa_install_rset_4.execute_stateful_alu(meta.rkey_index);
}
action get_rset_5() {
    sa_get_rset_5.execute_stateful_alu(meta.probe_rkey_index);
}
action install_rset_5() {
    sa_install_rset_5.execute_stateful_alu(meta.rkey_index);
}
action get_rset_6() {
    sa_get_rset_6.execute_stateful_alu(meta.probe_rkey_index);
}
action install_rset_6() {
    sa_install_rset_6.execute_stateful_alu(meta.rkey_index);
}
action get_rset_7() {
    sa_get_rset_7.execute_stateful_alu(meta.probe_rkey_index);
}
action install_rset_7() {
    sa_install_rset_7.execute_stateful_alu(meta.rkey_index);
}
action get_rset_8() {
    sa_get_rset_8.execute_stateful_alu(meta.probe_rkey_index);
}
action install_rset_8() {
    sa_install_rset_8.execute_stateful_alu(meta.rkey_index);
}
action get_rset_9() {
    sa_get_rset_9.execute_stateful_alu(meta.probe_rkey_index);
}
action install_rset_9() {
    sa_install_rset_9.execute_stateful_alu(meta.rkey_index);
}
action get_rset_10() {
    sa_get_rset_10.execute_stateful_alu(meta.probe_rkey_index);
}
action install_rset_10() {
    sa_install_rset_10.execute_stateful_alu(meta.rkey_index);
}
action get_rset_11() {
    sa_get_rset_11.execute_stateful_alu(meta.probe_rkey_index);
}
action install_rset_11() {
    sa_install_rset_11.execute_stateful_alu(meta.rkey_index);
}
action get_rset_12() {
    sa_get_rset_12.execute_stateful_alu(meta.probe_rkey_index);
}
action install_rset_12() {
    sa_install_rset_12.execute_stateful_alu(meta.rkey_index);
}
action get_rset_13() {
    sa_get_rset_13.execute_stateful_alu(meta.probe_rkey_index);
}
action install_rset_13() {
    sa_install_rset_13.execute_stateful_alu(meta.rkey_index);
}
action get_rset_14() {
    sa_get_rset_14.execute_stateful_alu(meta.probe_rkey_index);
}
action install_rset_14() {
    sa_install_rset_14.execute_stateful_alu(meta.rkey_index);
}
action get_rset_15() {
    sa_get_rset_15.execute_stateful_alu(meta.probe_rkey_index);
}
action install_rset_15() {
    sa_install_rset_15.execute_stateful_alu(meta.rkey_index);
}
action get_rset_16() {
    sa_get_rset_16.execute_stateful_alu(meta.probe_rkey_index);
}
action install_rset_16() {
    sa_install_rset_16.execute_stateful_alu(meta.rkey_index);
}

@pragma stage 4
table tab_get_rset_1 {
    actions {
        get_rset_1;
    }
    default_action: get_rset_1;
    size: 1;
}
@pragma stage 4
table tab_set_rset_1_a {
    actions {
        set_rset_1;
    }
    default_action: set_rset_1;
    size: 1;
}
@pragma stage 4
table tab_set_rset_1_b {
    actions {
        set_rset_1;
    }
    default_action: set_rset_1;
    size: 1;
}
@pragma stage 4
table tab_get_rset_2 {
    actions {
        get_rset_2;
    }
    default_action: get_rset_2;
    size: 1;
}
@pragma stage 4
table tab_install_rset_2_a {
    actions {
        install_rset_2;
    }
    default_action: install_rset_2;
    size: 1;
}
@pragma stage 4
table tab_install_rset_2_b {
    actions {
        install_rset_2;
    }
    default_action: install_rset_2;
    size: 1;
}
@pragma stage 4
table tab_get_rset_3 {
    actions {
        get_rset_3;
    }
    default_action: get_rset_3;
    size: 1;
}
@pragma stage 4
table tab_install_rset_3_a {
    actions {
        install_rset_3;
    }
    default_action: install_rset_3;
    size: 1;
}
@pragma stage 4
table tab_install_rset_3_b {
    actions {
        install_rset_3;
    }
    default_action: install_rset_3;
    size: 1;
}
@pragma stage 4
table tab_get_rset_4 {
    actions {
        get_rset_4;
    }
    default_action: get_rset_4;
    size: 1;
}
@pragma stage 4
table tab_install_rset_4_a {
    actions {
        install_rset_4;
    }
    default_action: install_rset_4;
    size: 1;
}
@pragma stage 4
table tab_install_rset_4_b {
    actions {
        install_rset_4;
    }
    default_action: install_rset_4;
    size: 1;
}
@pragma stage 5
table tab_get_rset_5 {
    actions {
        get_rset_5;
    }
    default_action: get_rset_5;
    size: 1;
}
@pragma stage 5
table tab_install_rset_5_a {
    actions {
        install_rset_5;
    }
    default_action: install_rset_5;
    size: 1;
}
@pragma stage 5
table tab_install_rset_5_b {
    actions {
        install_rset_5;
    }
    default_action: install_rset_5;
    size: 1;
}
@pragma stage 5
table tab_get_rset_6 {
    actions {
        get_rset_6;
    }
    default_action: get_rset_6;
    size: 1;
}
@pragma stage 5
table tab_install_rset_6_a {
    actions {
        install_rset_6;
    }
    default_action: install_rset_6;
    size: 1;
}
@pragma stage 5
table tab_install_rset_6_b {
    actions {
        install_rset_6;
    }
    default_action: install_rset_6;
    size: 1;
}
@pragma stage 5
table tab_get_rset_7 {
    actions {
        get_rset_7;
    }
    default_action: get_rset_7;
    size: 1;
}
@pragma stage 5
table tab_install_rset_7_a {
    actions {
        install_rset_7;
    }
    default_action: install_rset_7;
    size: 1;
}
@pragma stage 5
table tab_install_rset_7_b {
    actions {
        install_rset_7;
    }
    default_action: install_rset_7;
    size: 1;
}
@pragma stage 5
table tab_get_rset_8 {
    actions {
        get_rset_8;
    }
    default_action: get_rset_8;
    size: 1;
}
@pragma stage 5
table tab_install_rset_8_a {
    actions {
        install_rset_8;
    }
    default_action: install_rset_8;
    size: 1;
}
@pragma stage 5
table tab_install_rset_8_b {
    actions {
        install_rset_8;
    }
    default_action: install_rset_8;
    size: 1;
}
@pragma stage 6
table tab_get_rset_9 {
    actions {
        get_rset_9;
    }
    default_action: get_rset_9;
    size: 1;
}
@pragma stage 6
table tab_install_rset_9_a {
    actions {
        install_rset_9;
    }
    default_action: install_rset_9;
    size: 1;
}
@pragma stage 6
table tab_install_rset_9_b {
    actions {
        install_rset_9;
    }
    default_action: install_rset_9;
    size: 1;
}
@pragma stage 6
table tab_get_rset_10 {
    actions {
        get_rset_10;
    }
    default_action: get_rset_10;
    size: 1;
}
@pragma stage 6
table tab_install_rset_10_a {
    actions {
        install_rset_10;
    }
    default_action: install_rset_10;
    size: 1;
}
@pragma stage 6
table tab_install_rset_10_b {
    actions {
        install_rset_10;
    }
    default_action: install_rset_10;
    size: 1;
}
@pragma stage 6
table tab_get_rset_11 {
    actions {
        get_rset_11;
    }
    default_action: get_rset_11;
    size: 1;
}
@pragma stage 6
table tab_install_rset_11_a {
    actions {
        install_rset_11;
    }
    default_action: install_rset_11;
    size: 1;
}
@pragma stage 6
table tab_install_rset_11_b {
    actions {
        install_rset_11;
    }
    default_action: install_rset_11;
    size: 1;
}
@pragma stage 6
table tab_get_rset_12 {
    actions {
        get_rset_12;
    }
    default_action: get_rset_12;
    size: 1;
}
@pragma stage 6
table tab_install_rset_12_a {
    actions {
        install_rset_12;
    }
    default_action: install_rset_12;
    size: 1;
}
@pragma stage 6
table tab_install_rset_12_b {
    actions {
        install_rset_12;
    }
    default_action: install_rset_12;
    size: 1;
}
@pragma stage 7
table tab_get_rset_13 {
    actions {
        get_rset_13;
    }
    default_action: get_rset_13;
    size: 1;
}
@pragma stage 7
table tab_install_rset_13_a {
    actions {
        install_rset_13;
    }
    default_action: install_rset_13;
    size: 1;
}
@pragma stage 7
table tab_install_rset_13_b {
    actions {
        install_rset_13;
    }
    default_action: install_rset_13;
    size: 1;
}
@pragma stage 7
table tab_get_rset_14 {
    actions {
        get_rset_14;
    }
    default_action: get_rset_14;
    size: 1;
}
@pragma stage 7
table tab_install_rset_14_a {
    actions {
        install_rset_14;
    }
    default_action: install_rset_14;
    size: 1;
}
@pragma stage 7
table tab_install_rset_14_b {
    actions {
        install_rset_14;
    }
    default_action: install_rset_14;
    size: 1;
}
@pragma stage 7
table tab_get_rset_15 {
    actions {
        get_rset_15;
    }
    default_action: get_rset_15;
    size: 1;
}
@pragma stage 7
table tab_install_rset_15_a {
    actions {
        install_rset_15;
    }
    default_action: install_rset_15;
    size: 1;
}
@pragma stage 7
table tab_install_rset_15_b {
    actions {
        install_rset_15;
    }
    default_action: install_rset_15;
    size: 1;
}
@pragma stage 7
table tab_get_rset_16 {
    actions {
        get_rset_16;
    }
    default_action: get_rset_16;
    size: 1;
}
@pragma stage 7
table tab_install_rset_16_a {
    actions {
        install_rset_16;
    }
    default_action: install_rset_16;
    size: 1;
}
@pragma stage 7
table tab_install_rset_16_b {
    actions {
        install_rset_16;
    }
    default_action: install_rset_16;
    size: 1;
}

/*
   get/set/inc rset_num_ack
 */
blackbox stateful_alu sa_get_rset_num_ack {
    reg: reg_rset_num_ack;
    output_value: register_lo;
    output_dst: meta.rset_num_ack;
}
blackbox stateful_alu sa_set_rset_num_ack {
    reg: reg_rset_num_ack;
    update_lo_1_value: 1;
}
blackbox stateful_alu sa_inc_rset_num_ack {
    reg: reg_rset_num_ack;
    condition_lo: register_lo < NNODES;
    update_lo_1_predicate: condition_lo;
    update_lo_1_value: register_lo + 1;
}

action get_rset_num_ack() {
    sa_get_rset_num_ack.execute_stateful_alu(meta.rkey_index);
}
action set_rset_num_ack() {
    sa_set_rset_num_ack.execute_stateful_alu(meta.rkey_index);
}
action inc_rset_num_ack() {
    sa_inc_rset_num_ack.execute_stateful_alu(meta.rkey_index);
}

@pragma stage 2
table tab_get_rset_num_ack {
    actions {
        get_rset_num_ack;
    }
    default_action: get_rset_num_ack;
    size: 1;
}
@pragma stage 2
table tab_set_rset_num_ack_a {
    actions {
        set_rset_num_ack;
    }
    default_action: set_rset_num_ack;
    size: 1;
}
@pragma stage 2
table tab_set_rset_num_ack_b {
    actions {
        set_rset_num_ack;
    }
    default_action: set_rset_num_ack;
    size: 1;
}
@pragma stage 2
table tab_inc_rset_num_ack_a {
    actions {
        inc_rset_num_ack;
    }
    default_action: inc_rset_num_ack;
    size: 1;
}
@pragma stage 2
table tab_inc_rset_num_ack_b {
    actions {
        inc_rset_num_ack;
    }
    default_action: inc_rset_num_ack;
    size: 1;
}

/*
   get/set rkey/rset size
*/
blackbox stateful_alu sa_get_rkey_size {
    reg: reg_rkey_size;
    output_value: register_lo;
    output_dst: meta.rkey_size;
}
blackbox stateful_alu sa_get_rset_size {
    reg: reg_rset_size;
    output_value: register_lo;
    output_dst: meta.rset_size;
}
blackbox stateful_alu sa_set_rset_size {
    reg: reg_rset_size;
    update_lo_1_value: 1;
}
blackbox stateful_alu sa_inc_rset_size {
    reg: reg_rset_size;
    condition_lo: register_lo < MAX_REPLICAS;
    update_lo_1_predicate: condition_lo;
    update_lo_1_value: register_lo + 1;
    output_value: register_lo;
    output_dst: meta.rset_size;
}

action get_rkey_size() {
    sa_get_rkey_size.execute_stateful_alu(0);
}
action get_rset_size_a() {
    // for probing
    sa_get_rset_size.execute_stateful_alu(meta.probe_rkey_index);
}
action get_rset_size_b() {
    // for checking migration
    sa_get_rset_size.execute_stateful_alu(meta.rkey_index);
}
action set_rset_size() {
    sa_set_rset_size.execute_stateful_alu(meta.rkey_index);
}
action inc_rset_size() {
    sa_inc_rset_size.execute_stateful_alu(meta.rkey_index);
}

@pragma stage 0
table tab_get_rkey_size {
    actions {
        get_rkey_size;
    }
    default_action: get_rkey_size;
    size: 1;
}
@pragma stage 2
table tab_get_rset_size_a {
    // for probing
    actions {
        get_rset_size_a;
    }
    default_action: get_rset_size_a;
    size: 1;
}
@pragma stage 2
table tab_get_rset_size_b {
    // for checking migration
    actions {
        get_rset_size_b;
    }
    default_action: get_rset_size_b;
    size: 1;
}
@pragma stage 2
table tab_set_rset_size_a {
    actions {
        set_rset_size;
    }
    default_action: set_rset_size;
    size: 1;
}
@pragma stage 2
table tab_set_rset_size_b {
    actions {
        set_rset_size;
    }
    default_action: set_rset_size;
    size: 1;
}
@pragma stage 2
table tab_inc_rset_size_a {
    actions {
        inc_rset_size;
    }
    default_action: inc_rset_size;
    size: 1;
}
@pragma stage 2
table tab_inc_rset_size_b {
    actions {
        inc_rset_size;
    }
    default_action: inc_rset_size;
    size: 1;
}

/*
   get probe rkey/rset counter
 */
blackbox stateful_alu sa_get_probe_rkey_counter {
    reg: reg_probe_rkey_counter;
    condition_lo: register_lo + 1 >= meta.rkey_size;
    update_lo_1_predicate: condition_lo;
    update_lo_1_value: 0;
    update_lo_2_predicate: not condition_lo;
    update_lo_2_value: register_lo + 1;
    output_value: alu_lo;
    output_dst: meta.probe_rkey_index;
}
blackbox stateful_alu sa_get_probe_rset_counter {
    reg: reg_probe_rset_counter;
    condition_lo: register_lo + 1 >= meta.rset_size;
    update_lo_1_predicate: condition_lo;
    update_lo_1_value: 0;
    update_lo_2_predicate: not condition_lo;
    update_lo_2_value: register_lo + 1;
    output_value: alu_lo;
    output_dst: meta.probe_rset_index;
}

action get_probe_rkey_counter() {
    sa_get_probe_rkey_counter.execute_stateful_alu(0);
}
action get_probe_rset_counter() {
    sa_get_probe_rset_counter.execute_stateful_alu(meta.probe_rkey_index);
}

@pragma stage 1
table tab_get_probe_rkey_counter {
    actions {
        get_probe_rkey_counter;
    }
    default_action: get_probe_rkey_counter;
    size: 1;
}
@pragma stag 3
table tab_get_probe_rset_counter {
    actions {
        get_probe_rset_counter;
    }
    default_action: get_probe_rset_counter;
    size: 1;
}

/*
   set rkey/probe none
 */
action set_rkey_none() {
    modify_field(meta.rkey_index, RKEY_NONE);
}
action set_probe_none() {
    modify_field(meta.probe_rkey_index, RKEY_NONE);
}

table tab_set_rkey_none {
    actions {
        set_rkey_none;
    }
    default_action: set_rkey_none;
    size: 1;
}
table tab_set_probe_none {
    actions {
        set_probe_none;
    }
    default_action: set_probe_none;
    size: 1;
}

/*
   rw counter
 */
blackbox stateful_alu sa_get_rkey_read_counter {
    reg: reg_rkey_read_counter;
    output_value: register_lo;
    output_dst: pegasus.load;
}
blackbox stateful_alu sa_inc_rkey_read_counter {
    reg: reg_rkey_read_counter;
    update_lo_1_value: register_lo + 1;
}
blackbox stateful_alu sa_inc_rkey_write_counter {
    reg: reg_rkey_write_counter;
    update_lo_1_value: register_lo + 1;
    output_value: alu_lo;
    output_dst: pegasus.debug_load;
}

action get_rkey_read_counter() {
    sa_get_rkey_read_counter.execute_stateful_alu(meta.rkey_index);
}
action inc_rkey_read_counter() {
    sa_inc_rkey_read_counter.execute_stateful_alu(meta.rkey_index);
}
action inc_rkey_write_counter() {
    sa_inc_rkey_write_counter.execute_stateful_alu(meta.rkey_index);
}

table tab_get_rkey_read_counter {
    actions {
        get_rkey_read_counter;
    }
    default_action: get_rkey_read_counter;
    size: 1;
}
table tab_inc_rkey_read_counter {
    actions {
        inc_rkey_read_counter;
    }
    default_action: inc_rkey_read_counter;
    size: 1;
}
table tab_inc_rkey_write_counter {
    actions {
        inc_rkey_write_counter;
    }
    default_action: inc_rkey_write_counter;
    size: 1;
}

/*
   rkey migration
 */
action rkey_migration() {
    modify_field(pegasus.op, OP_MGR);
}

table tab_rkey_migration {
    actions {
        rkey_migration;
    }
    default_action: rkey_migration;
    size: 1;
}

/*
   copy header
 */
action copy_pegasus_header() {
    modify_field(meta.node, pegasus.node);
    modify_field(meta.load, pegasus.load);
}

table tab_copy_pegasus_header_a {
    actions {
        copy_pegasus_header;
    }
    default_action: copy_pegasus_header;
    size: 1;
}
table tab_copy_pegasus_header_b {
    actions {
        copy_pegasus_header;
    }
    default_action: copy_pegasus_header;
    size: 1;
}
table tab_copy_pegasus_header_c {
    actions {
        copy_pegasus_header;
    }
    default_action: copy_pegasus_header;
    size: 1;
}
table tab_copy_pegasus_header_d {
    actions {
        copy_pegasus_header;
    }
    default_action: copy_pegasus_header;
    size: 1;
}

/*
   write num replicas
 */
action write_num_replicas() {
    // Currently just replicate to MAX_REPLICAS - 1 nodes
    modify_field(pegasus.debug_node, MAX_REPLICAS - 1);
}

table tab_write_num_replicas {
    actions {
        write_num_replicas;
    }
    default_action : write_num_replicas;
    size : 1;
}

/*
   debug
*/
action debug() {
    modify_field(pegasus.debug_node, meta.node);
    modify_field(pegasus.debug_load, meta.load);
}

table tab_debug {
    actions {
        debug;
    }
    default_action: debug;
    size: 1;
}

control process_reply {
    apply(tab_get_rkey_size);
    if (meta.rkey_index != RKEY_NONE and pegasus.op == OP_REP_W) {
        // Check if the replicated write reply has a higher version number
        apply(tab_copy_pegasus_header_a);
        apply(tab_set_rkey_ver_curr_a);
        if (meta.ver_matched != 0) {
            apply(tab_set_rset_num_ack_a);
            apply(tab_set_rset_size_a);
            apply(tab_set_rkey_min_node_a);
            apply(tab_set_rset_1_a);
            apply(tab_l2_forward);
        } else {
            apply(tab_do_resubmit);
        }
    } else {
        // Probe rkey min node
        if (meta.rkey_size != 0) {
            apply(tab_get_probe_rkey_counter);
            apply(tab_get_rset_size_a);
            apply(tab_get_probe_rset_counter);
            if (meta.probe_rset_index == 0) {
                apply(tab_get_rset_1);
            } else if (meta.probe_rset_index == 1) {
                apply(tab_get_rset_2);
            } else if (meta.probe_rset_index == 2) {
                apply(tab_get_rset_3);
            } else if (meta.probe_rset_index == 3) {
                apply(tab_get_rset_4);
            } else if (meta.probe_rset_index == 4) {
                apply(tab_get_rset_5);
            } else if (meta.probe_rset_index == 5) {
                apply(tab_get_rset_6);
            } else if (meta.probe_rset_index == 6) {
                apply(tab_get_rset_7);
            } else if (meta.probe_rset_index == 7) {
                apply(tab_get_rset_8);
            } else if (meta.probe_rset_index == 8) {
                apply(tab_get_rset_9);
            } else if (meta.probe_rset_index == 9) {
                apply(tab_get_rset_10);
            } else if (meta.probe_rset_index == 10) {
                apply(tab_get_rset_11);
            } else if (meta.probe_rset_index == 11) {
                apply(tab_get_rset_12);
            } else if (meta.probe_rset_index == 12) {
                apply(tab_get_rset_13);
            } else if (meta.probe_rset_index == 13) {
                apply(tab_get_rset_14);
            } else if (meta.probe_rset_index == 14) {
                apply(tab_get_rset_15);
            } else if (meta.probe_rset_index == 15) {
                apply(tab_get_rset_16);
            }
            if (meta.node != RNODE_NONE) {
                apply(tab_get_queue_len);
            }
        } else {
            // Nothing to probe
            apply(tab_set_probe_none);
        }
        apply(tab_set_rkey_none);
        apply(tab_do_resubmit);
    }
}

control process_dec {
    apply(tab_copy_pegasus_header_b);
    apply(tab_dec_queue_len_a);
    apply(tab_do_resubmit);
}

control process_mgr {
    // Should never receive MGR message
    apply(tab_do_drop);
}

control process_mgr_req {
    apply(tab_l2_forward);
}

control process_mgr_ack {
    apply(tab_copy_pegasus_header_c);
    if (meta.rkey_index != RKEY_NONE) {
        apply(tab_set_rkey_ver_curr_b);
        if (meta.ver_matched != 0) {
            apply(tab_set_rset_num_ack_b);
            apply(tab_set_rset_size_b);
            apply(tab_set_rkey_min_node_b);
            apply(tab_set_rset_1_b);
            apply(tab_do_drop);
        } else {
            apply(tab_do_resubmit);
        }
    } else {
        apply(tab_do_drop);
    }
}

control process_request {
    if (meta.rkey_index != RKEY_NONE) {
        apply(tab_inc_rkey_rate_counter);
        if (pegasus.op == OP_GET) {
            process_replicated_read();
        } else {
            process_replicated_write();
        }
    } else {
        apply(tab_copy_pegasus_header_d);
    }
    apply(tab_inc_queue_len);
    apply(tab_do_resubmit);
}

control process_replicated_read {
    //apply(tab_get_rset_size_b);
    //if (meta.rset_size != MAX_REPLICAS) {
    apply(tab_get_rset_num_ack);
    if (meta.rset_num_ack != NNODES) {
        apply(tab_get_rkey_min_node);
    } else {
        apply(tab_get_min_node_a);
    }
}

control process_replicated_write {
    apply(tab_get_min_node_b);
}

control process_resubmit_reply {
    if (meta.rkey_index != RKEY_NONE) {
        if (pegasus.op == OP_REP_W) {
            // meta.node already copied in the first pass
            // another replica has received the latest write, install
            // it in the replication set
            apply(tab_compare_rkey_ver_curr_b);
            if (meta.ver_matched != 0) {
                apply(tab_inc_rset_num_ack_b);
                apply(tab_inc_rset_size_b);
                if (meta.rset_size == 1) {
                    apply(tab_install_rset_2_b);
                } else if (meta.rset_size == 2) {
                    apply(tab_install_rset_3_b);
                } else if (meta.rset_size == 3) {
                    apply(tab_install_rset_4_b);
                } else if (meta.rset_size == 4) {
                    apply(tab_install_rset_5_b);
                } else if (meta.rset_size == 5) {
                    apply(tab_install_rset_6_b);
                } else if (meta.rset_size == 6) {
                    apply(tab_install_rset_7_b);
                } else if (meta.rset_size == 7) {
                    apply(tab_install_rset_8_b);
                } else if (meta.rset_size == 8) {
                    apply(tab_install_rset_9_b);
                } else if (meta.rset_size == 9) {
                    apply(tab_install_rset_10_b);
                } else if (meta.rset_size == 10) {
                    apply(tab_install_rset_11_b);
                } else if (meta.rset_size == 11) {
                    apply(tab_install_rset_12_b);
                } else if (meta.rset_size == 12) {
                    apply(tab_install_rset_13_b);
                } else if (meta.rset_size == 13) {
                    apply(tab_install_rset_14_b);
                } else if (meta.rset_size == 14) {
                    apply(tab_install_rset_15_b);
                } else if (meta.rset_size == 15) {
                    apply(tab_install_rset_16_b);
                }
            }
        }
    } else {
        if (meta.probe_rkey_index != RKEY_NONE) {
            if (meta.node != RNODE_NONE) {
                apply(tab_compare_rkey_min_node);
            }
        }
    }
    apply(tab_l2_forward);
}

control process_resubmit_dec {
    apply(tab_dummy);
    apply(tab_dec_queue_len_b);
    apply(tab_do_drop);
}

control process_resubmit_mgr_ack {
    if (meta.rkey_index != RKEY_NONE) {
        apply(tab_compare_rkey_ver_curr_a);
        if (meta.ver_matched != 0) {
            apply(tab_inc_rset_num_ack_a);
            apply(tab_inc_rset_size_a);
            if (meta.rset_size == 1) {
                apply(tab_install_rset_2_a);
            } else if (meta.rset_size == 2) {
                apply(tab_install_rset_3_a);
            } else if (meta.rset_size == 3) {
                apply(tab_install_rset_4_a);
            } else if (meta.rset_size == 4) {
                apply(tab_install_rset_5_a);
            } else if (meta.rset_size == 5) {
                apply(tab_install_rset_6_a);
            } else if (meta.rset_size == 6) {
                apply(tab_install_rset_7_a);
            } else if (meta.rset_size == 7) {
                apply(tab_install_rset_8_a);
            } else if (meta.rset_size == 8) {
                apply(tab_install_rset_9_a);
            } else if (meta.rset_size == 9) {
                apply(tab_install_rset_10_a);
            } else if (meta.rset_size == 10) {
                apply(tab_install_rset_11_a);
            } else if (meta.rset_size == 11) {
                apply(tab_install_rset_12_a);
            } else if (meta.rset_size == 12) {
                apply(tab_install_rset_13_a);
            } else if (meta.rset_size == 13) {
                apply(tab_install_rset_14_a);
            } else if (meta.rset_size == 14) {
                apply(tab_install_rset_15_a);
            } else if (meta.rset_size == 15) {
                apply(tab_install_rset_16_a);
            }
        }
    }
    apply(tab_do_drop);
}

control process_resubmit_request {
    if (meta.rkey_index != RKEY_NONE) {
        if (pegasus.op == OP_GET) {
            apply(tab_get_rkey_ver_curr);
            apply(tab_inc_rkey_read_counter);
            /*
            apply(tab_get_rset_size_b);
            if (meta.rset_size != MAX_REPLICAS) {
                apply(tab_check_overload_rkey_min_node);
            }
            */
        } else {
            apply(tab_get_rkey_ver_next);
            apply(tab_get_rkey_read_counter);
            apply(tab_inc_rkey_write_counter);
        }
    }
    apply(tab_compare_min_node);
    /*
    if (meta.overload != 0) {
        apply(tab_rkey_migration);
    }
    if (meta.overload != 0 or meta.read_heavy != 0) {
        apply(tab_write_num_replicas);
    }
    */
    //apply(tab_debug);
    apply(tab_node_forward);
}

control ingress {
    if (0 == ig_intr_md.resubmit_flag) {
        if (valid(pegasus)) {
            if (pegasus.op == OP_DEC) {
                process_dec();
            } else if (pegasus.op == OP_MGR) {
                process_mgr();
            } else if (pegasus.op == OP_MGR_REQ) {
                process_mgr_req();
            } else {
                apply(tab_replicated_keys);
                if (pegasus.op == OP_REP_R or pegasus.op == OP_REP_W) {
                    process_reply();
                } else if (pegasus.op == OP_MGR_ACK) {
                    process_mgr_ack();
                } else {
                    process_request();
                }
            }
        } else {
            apply(tab_l2_forward);
        }
    } else {
        if (valid(pegasus)) {
            if (pegasus.op == OP_REP_R or pegasus.op == OP_REP_W) {
                process_resubmit_reply();
            } else if (pegasus.op == OP_DEC) {
                process_resubmit_dec();
            } else if (pegasus.op == OP_MGR_ACK) {
                process_resubmit_mgr_ack();
            } else {
                process_resubmit_request();
            }
        }
    }
}

/*************************************************************************
****************  E G R E S S   P R O C E S S I N G   *******************
*************************************************************************/

control egress {
}

/* -*- P4_16 -*- */
#include <core.p4>
#include <v1model.p4>

/*************************************************************************
*********************** H E A D E R S  ***********************************
*************************************************************************/

typedef bit<9>  egressSpec_t;
typedef bit<48> macAddr_t;
typedef bit<32> ip4Addr_t;
typedef bit<16> udpPort_t;
typedef bit<8>  op_t;
typedef bit<32> keyhash_t;
typedef bit<16> load_t;

const bit<16> TYPE_IPV4 = 0x800;
const bit<8> PROTO_UDP = 0x11;
const op_t OP_GET = 0x0;
const op_t OP_PUT = 0x1;
const op_t OP_DEL = 0x2;
const op_t OP_REP = 0x3;
const bit<16> PEGASUS_ID = 0x5047; //PG

header ethernet_t {
    macAddr_t dstAddr;
    macAddr_t srcAddr;
    bit<16>   etherType;
}

header ipv4_t {
    bit<4>    version;
    bit<4>    ihl;
    bit<8>    diffserv;
    bit<16>   totalLen;
    bit<16>   identification;
    bit<3>    flags;
    bit<13>   fragOffset;
    bit<8>    ttl;
    bit<8>    protocol;
    bit<16>   hdrChecksum;
    ip4Addr_t srcAddr;
    ip4Addr_t dstAddr;
}

header udp_t {
    udpPort_t   srcPort;
    udpPort_t   dstPort;
    bit<16>     len;
    bit<16>     checksum;
}

header pegasus_t {
    bit<16>     id;
    op_t        op;
    keyhash_t   keyhash;
    load_t      load;
}

struct metadata {
    egressSpec_t dstPort;
}

struct headers {
    ethernet_t   ethernet;
    ipv4_t       ipv4;
    udp_t        udp;
    pegasus_t    pegasus;
}

/*************************************************************************
*********************** STATEFUL MEMORY  *******************************
*************************************************************************/
register<load_t>(32) node_load;

/*************************************************************************
*********************** P A R S E R  ***********************************
*************************************************************************/

parser MyParser(packet_in packet,
                out headers hdr,
                inout metadata meta,
                inout standard_metadata_t standard_metadata) {

    state start {
	packet.extract(hdr.ethernet);
        transition select (hdr.ethernet.etherType) {
            TYPE_IPV4: parse_ipv4;
            default: accept;
	}
    }

    state parse_ipv4 {
        packet.extract(hdr.ipv4);
        transition select (hdr.ipv4.protocol) {
            PROTO_UDP: parse_udp;
            default: accept;
        }
    }

    state parse_udp {
        packet.extract(hdr.udp);
        transition select(packet.lookahead<pegasus_t>().id) {
            PEGASUS_ID : parse_pegasus;
            default: accept;
        }
    }

    state parse_pegasus {
        packet.extract(hdr.pegasus);
        transition accept;
    }
}


/*************************************************************************
************   C H E C K S U M    V E R I F I C A T I O N   *************
*************************************************************************/

control MyVerifyChecksum(inout headers hdr, inout metadata meta) {
    apply {  }
}


/*************************************************************************
**************  I N G R E S S   P R O C E S S I N G   *******************
*************************************************************************/

control MyIngress(inout headers hdr,
                  inout metadata meta,
                  inout standard_metadata_t standard_metadata) {
    action drop() {
        mark_to_drop();
    }

    action l2_forward(egressSpec_t port) {
        standard_metadata.egress_spec = port;
    }

    table tab_mac {
        key = {
            hdr.ethernet.dstAddr: exact;
        }
        actions = {
            l2_forward;
            drop;
        }
        size = 1024;
        default_action = drop();
    }

    action rkey_forward(macAddr_t macAddr, ip4Addr_t ip4Addr, egressSpec_t port) {
        hdr.ethernet.dstAddr = macAddr;
        hdr.ipv4.dstAddr = ip4Addr;
        standard_metadata.egress_spec = port;
    }

    table tab_rkey_forward {
        key = {
            meta.dstPort: exact;
        }
        actions = {
            rkey_forward;
            drop;
        }
        size = 32;
        default_action = drop();
    }

    action lookup_min_load() {
        // Currently only 2 nodes
        load_t min_load;
        load_t load;
        node_load.read(min_load, 1);
        node_load.read(load, 2);
        meta.dstPort = 1;
        if (load < min_load) {
            min_load = load;
            meta.dstPort = 2;
        }
        min_load = min_load + 1;
        node_load.write((bit<32>)meta.dstPort, min_load);
    }

    table tab_min_load {
        actions = {
            lookup_min_load;
        }
        default_action = lookup_min_load();
    }

    table tab_replicated_keys {
        key = {
            hdr.pegasus.keyhash: exact;
        }
        actions = {
            NoAction;
        }
        size = 8;
        default_action = NoAction();
    }

    apply {
        if (hdr.pegasus.isValid()) {
            if (tab_replicated_keys.apply().hit) {
                // If key is replicated, find the node
                // with the minimum load to forward to
                tab_min_load.apply();
                tab_rkey_forward.apply();
            } else {
                // If key not replicated, forward using L2
                tab_mac.apply();
            }
        } else if (hdr.ethernet.isValid()) {
            // All other packets use L2 forwarding
            tab_mac.apply();
        }
    }
}

/*************************************************************************
****************  E G R E S S   P R O C E S S I N G   *******************
*************************************************************************/

control MyEgress(inout headers hdr,
                 inout metadata meta,
                 inout standard_metadata_t standard_metadata) {
    apply {  }
}

/*************************************************************************
*************   C H E C K S U M    C O M P U T A T I O N   **************
*************************************************************************/

control MyComputeChecksum(inout headers hdr, inout metadata meta) {
     apply {
	update_checksum(
	    hdr.ipv4.isValid(),
            { hdr.ipv4.version,
	      hdr.ipv4.ihl,
              hdr.ipv4.diffserv,
              hdr.ipv4.totalLen,
              hdr.ipv4.identification,
              hdr.ipv4.flags,
              hdr.ipv4.fragOffset,
              hdr.ipv4.ttl,
              hdr.ipv4.protocol,
              hdr.ipv4.srcAddr,
              hdr.ipv4.dstAddr },
            hdr.ipv4.hdrChecksum,
            HashAlgorithm.csum16);
    }
}


/*************************************************************************
***********************  D E P A R S E R  *******************************
*************************************************************************/

control MyDeparser(packet_out packet, in headers hdr) {
    apply {
        packet.emit(hdr.ethernet);
        packet.emit(hdr.ipv4);
        packet.emit(hdr.udp);
        packet.emit(hdr.pegasus);
    }
}

/*************************************************************************
***********************  S W I T C H  *******************************
*************************************************************************/

V1Switch(
MyParser(),
MyVerifyChecksum(),
MyIngress(),
MyEgress(),
MyComputeChecksum(),
MyDeparser()
) main;
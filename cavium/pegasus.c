#include <string.h>
#include "pegasus.h"

/*
 * Hard-coded addresses
 */
#define MAX_NUM_NODES 16
static node_address_t node_addresses[MAX_NUM_NODES] = {
    [0] = { .mac_addr = {0xE4, 0x1D, 0x2D, 0x2E, 0x35, 0x11},
        .ip_addr = 0x0A0A0107,
        .port = 12345 },
    [1] = { .mac_addr = {0xE4, 0x1D, 0x2D, 0x2E, 0x35, 0x11},
        .ip_addr = 0x0A0A0107,
        .port = 12346 },
    [2] = { .mac_addr = {0xE4, 0x1D, 0x2D, 0x2E, 0x35, 0x11},
        .ip_addr = 0x0A0A0107,
        .port = 12347 },
    [3] = { .mac_addr = {0xE4, 0x1D, 0x2D, 0x2E, 0x35, 0x11},
        .ip_addr = 0x0A0A0107,
        .port = 12348 },
    [4] = { .mac_addr = {0xE4, 0x1D, 0x2D, 0x2E, 0x35, 0x11},
        .ip_addr = 0x0A0A0107,
        .port = 12349 },
    [5] = { .mac_addr = {0xE4, 0x1D, 0x2D, 0x2E, 0x35, 0x11},
        .ip_addr = 0x0A0A0107,
        .port = 12350 },
    [6] = { .mac_addr = {0xE4, 0x1D, 0x2D, 0x2E, 0x35, 0x11},
        .ip_addr = 0x0A0A0107,
        .port = 12351 },
    [7] = { .mac_addr = {0xE4, 0x1D, 0x2D, 0x2E, 0x35, 0x11},
        .ip_addr = 0x0A0A0107,
        .port = 12352 },
};
#define PORT_ZERO 12345

/*
 * Global variables
 */
static size_t num_nodes = 1;
static node_load_t node_loads[MAX_NUM_NODES];
static float load_constant = 1.0;

/*
 * Static function declarations
 */
static void convert_endian(void *dst, const void *src, size_t n);
static packet_type_t match_pegasus_packet(uint64_t buf);
static int decode_kv_packet(uint64_t buf, kv_packet_t *kv_packet);
static uint64_t key_hash(const char* key);
static void forward_to_node(uint64_t buf, int node_id);
static uint64_t checksum(const void *buf, size_t n);
static int decode_controller_packet(uint64_t buf, reset_t *reset);
static void process_kv_packet(uint64_t buf, const kv_packet_t *kv_packet);
static int port_to_node_id(uint16_t port);
static int key_to_node_id(const char *key);

/*
 * Static function definitions
 */
static void convert_endian(void *dst, const void *src, size_t n)
{
  size_t i;
  uint8_t *dptr, *sptr;

  dptr = (uint8_t*)dst;
  sptr = (uint8_t*)src;

  for (i = 0; i < n; i++) {
    *(dptr + i) = *(sptr + n - i - 1);
  }
}

static packet_type_t match_pegasus_packet(uint64_t buf)
{
    identifier_t identifier;
    convert_endian(&identifier, (const void *)(buf+APP_HEADER), sizeof(identifier_t));
    if (identifier == KV_ID) {
        return KV;
    } else if (identifier == CONTROLLER_ID) {
        return CONTROLLER;
    } else {
        return UNKNOWN;
    }
}

static int decode_kv_packet(uint64_t buf, kv_packet_t *kv_packet)
{
    uint64_t ptr = buf;
    ptr += sizeof(identifier_t);
    type_t type = *(type_t *)ptr;
    ptr += sizeof(type_t);
    if (type != TYPE_REQUEST && type != TYPE_REPLY) {
        return -1;
    }
    kv_packet->type = type;
    if (kv_packet->type == TYPE_REQUEST) {
        ptr += sizeof(client_id_t) + sizeof(req_id_t);
        kv_packet->op_type = *(op_type_t *)ptr;
        ptr += sizeof(op_type_t) + sizeof(key_len_t);
        kv_packet->key = (const char*)ptr;
    }
    return 0;
}

static uint64_t key_hash(const char* key)
{
    uint64_t hash = 5381;
    size_t i;
    for (i = 0; i < strlen(key); i++) {
        hash = ((hash << 5) + hash) + (uint64_t)key[i];
    }
    return hash;
}

static void forward_to_node(uint64_t buf, int node_id)
{
    // Modify MAC address
    size_t i;
    for (i = 0; i < 6; i++) {
        *(uint8_t *)(buf + ETH_DST + i) = node_addresses[node_id].mac_addr[i];
    }

    // Modify IP address
    *(uint32_t *)(buf + IP_DST) = node_addresses[node_id].ip_addr;
    *(uint16_t *)(buf + IP_CKSUM) = 0;
    *(uint16_t *)(buf + IP_CKSUM) = (uint16_t)checksum((void *)(buf + IP_HEADER), IP_SIZE);

    // Modify UDP address
    *(uint16_t *)(buf + UDP_DST) = node_addresses[node_id].port;
    *(uint16_t *)(buf + UDP_CKSUM) = 0;
}

static uint64_t checksum(const void *buf, size_t n)
{
    uint64_t sum;
    uint16_t *ptr = (uint16_t *)buf;
    size_t i;
    for (i = 0, sum = 0; i < (n / 2); i++) {
        sum += *ptr++;
    }
    sum = (sum >> 16) + (sum & 0xFFFF);
    sum += (sum >> 16);
    return ~sum;
}

static int decode_controller_packet(uint64_t buf, reset_t *reset)
{
    uint64_t ptr = buf;
    ptr += sizeof(identifier_t);
    type_t type = *(type_t *)ptr;
    ptr += sizeof(type_t);
    if (type != TYPE_RESET) {
        return -1;
    }
    convert_endian(&reset->num_nodes, (const void *)ptr, sizeof(num_nodes_t));
    return 0;
}

static void process_kv_packet(uint64_t buf, const kv_packet_t *kv_packet)
{
    if (kv_packet->type == TYPE_REQUEST) {
        int node_id = key_to_node_id(kv_packet->key);
        node_loads[node_id].iload++;
        forward_to_node(buf, node_id);
    } else if (kv_packet->type == TYPE_REPLY) {
        int node_id = port_to_node_id(*(uint16_t *)(buf+UDP_SRC));
        node_loads[node_id].iload--;
    }
}

static int port_to_node_id(uint16_t port)
{
    return port - PORT_ZERO;
}

static int key_to_node_id(const char *key)
{
    size_t i;
    uint64_t total_iload = 0;
    for (i = 0; i < num_nodes; i++) {
        total_iload += node_loads[i].iload;
    }
    uint64_t avg_iload = total_iload / num_nodes;

    int node_id = key_hash(key) % num_nodes;
    while (node_loads[node_id].iload > load_constant * avg_iload) {
        node_id = (node_id + 1) % num_nodes;
    }
    return node_id;
}

/*
 * Public function definitions
 */
void pegasus_packet_proc(uint64_t buf)
{
    switch (match_pegasus_packet(buf)) {
        case KV: {
            kv_packet_t kv_packet;
            if (decode_kv_packet(buf+APP_HEADER, &kv_packet) == 0) {
                process_kv_packet(buf, &kv_packet);
            }
            break;
        }
        case CONTROLLER: {
            reset_t reset;
            if (decode_controller_packet(buf+APP_HEADER, &reset) == 0) {
                num_nodes = reset.num_nodes;
                size_t i;
                for (i = 0; i < num_nodes; i++) {
                    node_loads[i].iload = 0;
                }
            }
            break;
        }
        default:
            return;
    }
}
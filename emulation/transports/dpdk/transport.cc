#include <rte_eal.h>
#include <rte_lcore.h>
#include <rte_ethdev.h>
#include <rte_mbuf.h>

#include <logger.h>
#include <transports/dpdk/transport.h>
#include <transports/dpdk/configuration.h>

#define RTE_RX_DESC 1024
#define RTE_TX_DESC 1024
#define MAX_PKT_BURST 32
#define MEMPOOL_CACHE_SIZE 256

#define ETHER_HDR_SIZE 14
#define IPV4_VER 4
#define IPV4_HDR_SIZE 5
#define IPV4_TTL 0xFF
#define IPV4_PROTO_UDP 0x11

static int transport_thread(void *arg)
{
    DPDKTransport *transport = (DPDKTransport*)arg;
    transport->run_internal();
    return 0;
}

static void construct_arguments(const Configuration *config, int argc, char **argv)
{
    argv[0] = new char[strlen("command")+1];
    strcpy(argv[0], "command");
    argv[1] = new char[strlen("-l")+1];
    strcpy(argv[1], "-l");
    std::string cores;
    char app_core[16], transport_core[16];
    sprintf(app_core, "%d", config->app_core);
    sprintf(transport_core, "%d", config->transport_core);
    cores.append(app_core);
    cores.append(",");
    cores.append(transport_core);
    argv[2] = new char[cores.length()+1];
    strcpy(argv[2], cores.c_str());
    argv[3] = new char[strlen("--proc-type=auto")+1];
    strcpy(argv[3], "--proc-type=auto");
}

DPDKTransport::DPDKTransport(const Configuration *config)
    : Transport(config), portid(0), status(STOPPED)
{
    this->argc = 4;
    this->argv = new char*[this->argc];
    unsigned nb_mbufs;
    uint16_t nb_ports, nb_rxd = RTE_RX_DESC, nb_txd = RTE_TX_DESC;
    struct rte_eth_rxconf rxconf;
    struct rte_eth_txconf txconf;
    struct rte_eth_conf port_conf;
    struct rte_eth_dev_info dev_info;
    rte_proc_type_t proc_type;
    const DPDKConfiguration *dpdkconfig = static_cast<const DPDKConfiguration*>(config);
    this->rx_queue_id = dpdkconfig->queue_id;
    this->tx_queue_id = dpdkconfig->queue_id;

    // Initialize
    construct_arguments(config, this->argc, this->argv);
    if (rte_eal_init(argc, argv) < 0) {
        panic("rte_eal_init failed");
    }

    proc_type = rte_eal_process_type();

    if ((nb_ports = rte_eth_dev_count_avail()) == 0) {
        panic("No available Ethernet ports");
    }

    // Create mbuf pool
    nb_mbufs = nb_rxd + nb_txd + MAX_PKT_BURST + MEMPOOL_CACHE_SIZE;
    if (proc_type == RTE_PROC_PRIMARY) {
        this->pktmbuf_pool = rte_pktmbuf_pool_create("pktmbuf_pool",
                                                     nb_mbufs,
                                                     MEMPOOL_CACHE_SIZE,
                                                     0,
                                                     RTE_MBUF_DEFAULT_BUF_SIZE,
                                                     rte_socket_id());
    } else {
        this->pktmbuf_pool = rte_mempool_lookup("pktmbuf_pool");
    }

    if (this->pktmbuf_pool == nullptr) {
        panic("rte_pktmbuf_pool_create failed");
    }

    if (proc_type == RTE_PROC_PRIMARY) {
        // Initialize port
        memset(&port_conf, 0, sizeof(port_conf));
        port_conf.txmode.mq_mode = ETH_MQ_TX_NONE;

        if (rte_eth_dev_info_get(this->portid, &dev_info) != 0) {
            panic("rte_eth_dev_info_get failed");
        }
        if (dev_info.tx_offload_capa & DEV_TX_OFFLOAD_MBUF_FAST_FREE) {
            port_conf.txmode.offloads |= DEV_TX_OFFLOAD_MBUF_FAST_FREE;
        }
        if (rte_eth_dev_configure(this->portid,
                                  dpdkconfig->num_queues,
                                  dpdkconfig->num_queues,
                                  &port_conf) < 0) {
            panic("rte_eth_dev_configure failed");
        }
        if (rte_eth_dev_adjust_nb_rx_tx_desc(this->portid, &nb_rxd, &nb_txd) < 0) {
            panic("rte_eth_dev_adjust_nb_rx_tx_desc failed");
        }

        // Initialize RX queue
        rxconf = dev_info.default_rxconf;
        rxconf.offloads = port_conf.rxmode.offloads;
        for (int qid = 0; qid < dpdkconfig->num_queues; qid++) {
            if (rte_eth_rx_queue_setup(this->portid,
                                       qid,
                                       nb_rxd,
                                       rte_eth_dev_socket_id(this->portid),
                                       &rxconf,
                                       this->pktmbuf_pool) < 0) {
                panic("rte_eth_rx_queue_setup failed");
            }
        }

        // Initialize TX queue
        txconf = dev_info.default_txconf;
        txconf.offloads = port_conf.txmode.offloads;
        for (int qid = 0; qid < dpdkconfig->num_queues; qid++) {
            if (rte_eth_tx_queue_setup(this->portid,
                                       qid,
                                       nb_txd,
                                       rte_eth_dev_socket_id(this->portid),
                                       &txconf) < 0) {
                panic("rte_eth_tx_queue_setup failed");
            }
        }

        // Start device
        if (rte_eth_dev_start(this->portid) < 0) {
            panic("rte_eth_dev_start failed");
        }
        if (rte_eth_promiscuous_enable(this->portid) != 0) {
            panic("rte_eth_promiscuous_enable failed");
        }
    }
}

DPDKTransport::~DPDKTransport()
{
    rte_eth_dev_stop(this->portid);
    rte_eth_dev_close(this->portid);
    if (this->argv != nullptr) {
        for (int i = 0; i < this->argc; i++) {
            delete this->argv[i];
        }
        delete [] this->argv;
    }
}

void DPDKTransport::send_message(const Message &msg, const Address &addr)
{
    struct rte_mbuf *m;
    struct rte_ether_hdr *ether_hdr;
    struct rte_ipv4_hdr *ip_hdr;
    struct rte_udp_hdr *udp_hdr;
    void *dgram;
    uint16_t sent;
    const DPDKAddress &dst_addr = static_cast<const DPDKAddress&>(addr);
    const DPDKAddress &src_addr = static_cast<const DPDKAddress&>(*this->config->my_address());

    /* Allocate mbuf */
    m = rte_pktmbuf_alloc(this->pktmbuf_pool);
    if (m == nullptr) {
        panic("Failed to allocate rte_mbuf");
    }
    /* Ethernet header */
    ether_hdr = (struct rte_ether_hdr*)rte_pktmbuf_append(m, ETHER_HDR_SIZE);
    if (ether_hdr == nullptr) {
        panic("Failed to allocate Ethernet header");
    }
    ether_hdr->ether_type = rte_cpu_to_be_16(RTE_ETHER_TYPE_IPV4);
    memcpy(&ether_hdr->d_addr, &dst_addr.ether_addr, sizeof(struct rte_ether_addr));
    memcpy(&ether_hdr->s_addr, &src_addr.ether_addr, sizeof(struct rte_ether_addr));
    /* IP header */
    ip_hdr = (struct rte_ipv4_hdr*)rte_pktmbuf_append(m, IPV4_HDR_SIZE * RTE_IPV4_IHL_MULTIPLIER);
    if (ip_hdr == nullptr) {
        panic("Failed to allocated IP header");
    }
    ip_hdr->version_ihl = (IPV4_VER << 4) | IPV4_HDR_SIZE;
    ip_hdr->type_of_service = 0;
    ip_hdr->total_length = rte_cpu_to_be_16(IPV4_HDR_SIZE * RTE_IPV4_IHL_MULTIPLIER +
                                            sizeof(struct rte_udp_hdr) +
                                            msg.len());
    ip_hdr->packet_id = 0;
    ip_hdr->fragment_offset = 0;
    ip_hdr->time_to_live = IPV4_TTL;
    ip_hdr->next_proto_id = IPV4_PROTO_UDP;
    ip_hdr->hdr_checksum = 0;
    ip_hdr->src_addr = src_addr.ip_addr;
    ip_hdr->dst_addr = dst_addr.ip_addr;
    ip_hdr->hdr_checksum = rte_ipv4_cksum(ip_hdr);
    /* UDP header */
    udp_hdr = (struct rte_udp_hdr*)rte_pktmbuf_append(m, sizeof(struct rte_udp_hdr));
    if (udp_hdr == nullptr) {
        panic("Failed to allocate UDP header");
    }
    udp_hdr->src_port = src_addr.udp_port;
    udp_hdr->dst_port = dst_addr.udp_port;
    udp_hdr->dgram_len = rte_cpu_to_be_16(sizeof(struct rte_udp_hdr) + msg.len());
    udp_hdr->dgram_cksum = 0;
    /* Datagram */
    dgram = rte_pktmbuf_append(m, msg.len());
    if (dgram == nullptr) {
        panic("Failed to allocate data gram");
    }
    memcpy(dgram, msg.buf(), msg.len());
    /* Send packet */
    sent = rte_eth_tx_burst(this->portid, this->tx_queue_id, &m, 1);
    if (sent < 1) {
        panic("Failed to send packet");
    }
}

void DPDKTransport::run(void)
{
    this->status = RUNNING;
    if (rte_eal_mp_remote_launch(transport_thread, this, SKIP_MASTER) != 0) {
        panic("rte_eal_mp_remote_launch failed");
    }
}

void DPDKTransport::stop(void)
{
    this->status = STOPPED;
}

void DPDKTransport::wait(void)
{
    uint16_t lcore_id;
    RTE_LCORE_FOREACH_SLAVE(lcore_id) {
        if (rte_eal_wait_lcore(lcore_id) < 0) {
            printf("rte_eal_wait_lcore failed on core %d\n", lcore_id);
        }
    }
}

void DPDKTransport::run_internal()
{
    uint16_t nb_rx, i;
    struct rte_mbuf *pkt_burst[MAX_PKT_BURST];
    struct rte_mbuf *m;
    size_t offset;

    while (this->status == DPDKTransport::RUNNING) {
        nb_rx = rte_eth_rx_burst(this->portid, this->rx_queue_id, pkt_burst, MAX_PKT_BURST);
        for (i = 0; i < nb_rx; i++) {
            m = pkt_burst[i];
            /* Parse packet header */
            struct rte_ether_hdr *ether_hdr;
            struct rte_ipv4_hdr *ip_hdr;
            struct rte_udp_hdr *udp_hdr;
            offset = 0;
            ether_hdr = rte_pktmbuf_mtod_offset(m, struct rte_ether_hdr*, offset);
            offset += ETHER_HDR_SIZE;
            ip_hdr = rte_pktmbuf_mtod_offset(m, struct rte_ipv4_hdr*, offset);
            offset += (ip_hdr->version_ihl & RTE_IPV4_HDR_IHL_MASK) * RTE_IPV4_IHL_MULTIPLIER;
            udp_hdr = rte_pktmbuf_mtod_offset(m, struct rte_udp_hdr*, offset);
            offset += sizeof(struct rte_udp_hdr);

            if (filter_packet(DPDKAddress(ether_hdr->d_addr, ip_hdr->dst_addr, udp_hdr->dst_port))) {
                /* Construct source address */
                DPDKAddress addr(ether_hdr->s_addr, ip_hdr->src_addr, udp_hdr->src_port);

                /* Upcall to transport receiver */
                Message msg(rte_pktmbuf_mtod_offset(m, void*, offset),
                        rte_be_to_cpu_16(udp_hdr->dgram_len) - sizeof(struct rte_udp_hdr),
                        false);
                this->receiver->receive_message(msg, addr);
            }
            rte_pktmbuf_free(m);
        }
    }
}

bool DPDKTransport::filter_packet(const DPDKAddress &addr) const
{
    const DPDKAddress *my_addr = static_cast<const DPDKAddress*>(this->config->my_address());

    if (memcmp(&addr.ether_addr, &my_addr->ether_addr, sizeof(struct rte_ether_addr)) != 0) {
        return false;
    }
    if (addr.ip_addr != my_addr->ip_addr) {
        return false;
    }
    if (addr.udp_port != my_addr->udp_port) {
        return false;
    }
    return true;
}

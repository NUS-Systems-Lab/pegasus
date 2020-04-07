#ifndef _DPDK_TRANSPORT_H_
#define _DPDK_TRANSPORT_H_

#include <rte_mempool.h>

#include <transport.h>

class DPDKTransport : public Transport {
public:
    DPDKTransport(const Configuration *config);
    ~DPDKTransport();

    virtual void send_message(const Message &msg, const Address &addr) override final;
    virtual void run() override final;
    virtual void stop() override final;
    virtual void wait() override final;

    void run_internal();

private:
    struct rte_mempool *pktmbuf_pool;
    uint16_t portid;
    volatile enum {
        RUNNING,
        STOPPED,
    } status;
};

#endif /* _DPDK_TRANSPORT_H_ */
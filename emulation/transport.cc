#include <assert.h>
#include <sys/socket.h>
#include <unistd.h>
#include <fcntl.h>
#include "transport.h"
#include "logger.h"

Transport::Transport()
    : event_base(nullptr), socket_fd(-1) {};

Transport::~Transport()
{
    if (this->socket_fd > 0) {
        close(socket_fd);
    }

    for (auto event : this->events) {
        event_free(event);
    }

    if (this->event_base != nullptr) {
        event_base_free(this->event_base);
    }
}

void
Transport::register_node(TransportReceiver *receiver,
                         Configuration *config,
                         int node_id)
{
    assert(receiver != nullptr);
    assert(config != nullptr);
    this->receiver = receiver;
    this->config = config;

    // Setup socket
    this->socket_fd = socket(AF_INET, SOCK_DGRAM, 0);
    if (this->socket_fd == -1) {
        panic("Failed to create socket");
    }

    if (fcntl(this->socket_fd, F_SETFL, O_NONBLOCK, 1) == -1) {
        panic("Failed to set O_NONBLOCK");
    }

    // Bind to address
    struct sockaddr_in sin;
    if (node_id == -1) {
        // Client can bind to any port
        memset(&sin, 0, sizeof(sin));
        sin.sin_family = AF_INET;
        sin.sin_port = 0;
    } else {
        assert(config->addresses.count(node_id) > 0);
        NodeAddress addr = config->addresses.at(node_id);
        sin = addr.sin;
    }

    if (bind(this->socket_fd, (sockaddr *)&sin, sizeof(sin)) != 0) {
        panic("Failed to bind port");
    }

    // Create event base
    this->event_base = event_base_new();
    if (this->event_base == nullptr) {
        panic("Failed to create new libevent event base");
    }

    // Add socket event
    struct event *sock_ev = event_new(this->event_base,
                                      this->socket_fd,
                                      EV_READ | EV_PERSIST,
                                      socket_callback,
                                      (void *)this);
    if (sock_ev == nullptr) {
        panic("Failed to create new event");
    }

    event_add(sock_ev, NULL);
    this->events.push_back(sock_ev);

    // Add signal events
    struct event *term_ev = evsignal_new(this->event_base,
                                         SIGTERM,
                                         &Transport::signal_callback,
                                         (void *)this);
    struct event *int_ev = evsignal_new(this->event_base,
                                        SIGINT,
                                        signal_callback,
                                        (void *)this);
    event_add(term_ev, NULL);
    this->events.push_back(term_ev);
    event_add(int_ev, NULL);
    this->events.push_back(int_ev);
}

void
Transport::run()
{
    event_base_dispatch(this->event_base);
}

void
Transport::send_message(const std::string &msg, const sockaddr &addr)
{
    if (sendto(this->socket_fd, msg.c_str(), msg.size()+1, 0, &addr, sizeof(addr)) == -1) {
        printf("Failed to send message\n");
    }
}

void
Transport::send_message_to_node(const std::string &msg, int dst_node_id)
{
    assert(dst_node_id < this->config->num_nodes);
    NodeAddress addr = this->config->addresses.at(dst_node_id);
    send_message(msg, *(struct sockaddr *)&addr.sin);
}

void
Transport::socket_callback(evutil_socket_t fd, short what, void *arg)
{
    if (what & EV_READ) {
        Transport *transport = (Transport *)arg;
        transport->on_readable(fd);
    }
}

void
Transport::signal_callback(evutil_socket_t fd, short what, void *arg)
{
    Transport *transport = (Transport *)arg;
    event_base_loopbreak(transport->event_base);
}

void
Transport::on_readable(int fd)
{
    const int BUFSIZE = 65535;
    char buf[BUFSIZE];
    struct sockaddr src_addr;
    socklen_t addrlen = sizeof(src_addr);
    ssize_t ret;

    ret = recvfrom(fd, buf, BUFSIZE, 0, &src_addr, &addrlen);
    if (ret == -1) {
        if (errno == EAGAIN || errno == EWOULDBLOCK) {
            return;
        }
        printf("Failed to receive message\n");
    }

    this->receiver->receive_message(std::string(buf), src_addr);
}
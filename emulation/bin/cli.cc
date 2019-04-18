#include "node.h"
#include "transport.h"
#include "memcachekv/config.h"
#include "memcachekv/message.h"
#include "memcachekv/cli_client.h"

using std::string;
using namespace memcachekv;

int main(int argc, char *argv[])
{
    if (argc < 3) {
        printf("usage: cli <config_file> <node_type> <op_type> <key> (<value>)\n");
        exit(1);
    }
    const char *config_file_path = argv[1];
    int node_type = stoi(string(argv[2]));

    MemcacheKVConfig *config;
    MessageCodec *codec;
    if (node_type == 0) {
        config = new MemcacheKVConfig(config_file_path, MemcacheKVConfig::ROUTER);
        codec = new WireCodec(true);
    } else if (node_type == 1) {
        config = new MemcacheKVConfig(config_file_path, MemcacheKVConfig::STATIC);
        codec = new WireCodec(false);
    } else {
        config = new MemcacheKVConfig(config_file_path, MemcacheKVConfig::NETCACHE);
        codec = new NetcacheCodec();
    }
    config->node_id = -1;
    config->n_transport_threads = 1;
    config->terminating = true;
    CLIClient cli(config, codec);
    Node node(config);
    node.register_app(&cli);

    node.run(0);

    delete codec;
    delete config;

    return 0;
}

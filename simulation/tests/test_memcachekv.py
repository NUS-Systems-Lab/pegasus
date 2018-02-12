"""
test_memcachekv.py: Unit tests for MemcacheKV.
"""

import unittest
import pegasus.node
import pegasus.simulator
import pegasus.applications.kv as kv
import pegasus.applications.kvimpl.memcachekv as memcachekv
import pegasus.param as param

class MemcacheKVSingleAppTest(unittest.TestCase):
    def setUp(self):
        self.kvapp = memcachekv.MemcacheKV(None,
                                           kv.KVStats())

    def test_basic(self):
        result, value = self.kvapp._execute_op(kv.Operation(kv.Operation.Type.PUT, 'k1', 'v1'))
        self.assertEqual(result, kv.Result.OK)
        self.assertEqual(len(value), 0)
        result, value = self.kvapp._execute_op(kv.Operation(kv.Operation.Type.GET, 'k1'))
        self.assertEqual(result, kv.Result.OK)
        self.assertEqual(value, 'v1')
        result, value = self.kvapp._execute_op(kv.Operation(kv.Operation.Type.GET, 'k2'))
        self.assertEqual(result, kv.Result.NOT_FOUND)
        self.assertEqual(len(value), 0)
        result, value = self.kvapp._execute_op(kv.Operation(kv.Operation.Type.DEL, 'k1'))
        self.assertEqual(result, kv.Result.OK)
        self.assertEqual(len(value), 0)
        result, value = self.kvapp._execute_op(kv.Operation(kv.Operation.Type.GET, 'k1'))
        self.assertEqual(result, kv.Result.NOT_FOUND)
        self.assertEqual(len(value), 0)


class ClientServerTest(unittest.TestCase):
    class SingleServerConfig(memcachekv.MemcacheKVConfiguration):
        def __init__(self, cache_nodes, db_node):
            assert len(cache_nodes) == 1
            super().__init__(cache_nodes, db_node)

        def key_to_node(self, key):
            return self.cache_nodes[0]

    def setUp(self):
        rack = pegasus.node.Rack()
        self.client = pegasus.node.Node(rack, 0)
        self.server = pegasus.node.Node(rack, 1)
        self.stats = kv.KVStats()
        self.client_app = memcachekv.MemcacheKV(None,
                                                self.stats)
        self.client_app.register_config(self.SingleServerConfig([self.server], None))
        self.server_app = memcachekv.MemcacheKV(None,
                                                self.stats)
        self.client.register_app(self.client_app)
        self.server.register_app(self.server_app)

    def test_basic(self):
        timer = 0
        self.client_app._execute(kv.Operation(kv.Operation.Type.PUT, 'k1', 'v1'),
                                 timer)
        timer += param.MAX_PROPG_DELAY + param.MAX_PKT_PROC_LTC
        self.client.run(timer)
        self.server.run(timer)
        self.assertEqual(self.server_app._store['k1'], 'v1')
        self.assertEqual(self.stats.received_replies[kv.Operation.Type.PUT],
                         0)
        timer += param.MAX_PROPG_DELAY + param.MAX_PKT_PROC_LTC
        self.client.run(timer)
        self.server.run(timer)
        self.assertEqual(self.stats.received_replies[kv.Operation.Type.PUT],
                         1)
        self.client_app._execute(kv.Operation(kv.Operation.Type.GET, 'k1'),
                                 timer)
        for _ in range(2):
            timer += param.MAX_PROPG_DELAY + param.MAX_PKT_PROC_LTC
            self.client.run(timer)
            self.server.run(timer)
        self.assertEqual(self.stats.received_replies[kv.Operation.Type.PUT],
                         1)
        self.assertEqual(self.stats.received_replies[kv.Operation.Type.GET],
                         1)
        self.assertEqual(self.stats.cache_hits, 1)
        self.assertEqual(self.stats.cache_misses, 0)
        self.client_app._execute(kv.Operation(kv.Operation.Type.GET, 'k2'),
                                 timer)
        for _ in range(2):
            timer += param.MAX_PROPG_DELAY + param.MAX_PKT_PROC_LTC
            self.client.run(timer)
            self.server.run(timer)
        self.assertEqual(self.stats.received_replies[kv.Operation.Type.PUT],
                         1)
        self.assertEqual(self.stats.received_replies[kv.Operation.Type.GET],
                         2)
        self.assertEqual(self.stats.cache_hits, 1)
        self.assertEqual(self.stats.cache_misses, 1)
        self.assertEqual(len(self.client_app._store), 0)
        self.assertEqual(len(self.server_app._store), 1)


class SimulatorTest(unittest.TestCase):
    class StaticConfig(memcachekv.MemcacheKVConfiguration):
        def __init__(self, cache_nodes, db_node):
            super().__init__(cache_nodes, db_node)

        def key_to_node(self, key):
            index = sum(map(lambda x : ord(x), key)) % len(self.cache_nodes)
            return self.cache_nodes[index]

    class SimpleGenerator(kv.KVWorkloadGenerator):
        def __init__(self):
            self.ops = [(kv.Operation(kv.Operation.Type.PUT,
                                      "k1",
                                      "v1"),
                         0),
                        (kv.Operation(kv.Operation.Type.PUT,
                                      "k2",
                                      "v2"),
                         round(0.5*param.propg_delay())),
                        (kv.Operation(kv.Operation.Type.GET,
                                      "k1"),
                         round(1.2*param.propg_delay())),
                        (kv.Operation(kv.Operation.Type.GET,
                                      "k3"),
                         round(1.7*param.propg_delay())),
                        (kv.Operation(kv.Operation.Type.PUT,
                                      "k3",
                                      "v3"),
                         round(2.5*param.propg_delay())),
                        (kv.Operation(kv.Operation.Type.GET,
                                      "k3"),
                         round(3*param.propg_delay())),
                        (kv.Operation(kv.Operation.Type.GET,
                                      "k2"),
                         round(3.9*param.propg_delay())),
                        (kv.Operation(kv.Operation.Type.DEL,
                                      "k1"),
                         round(4.3*param.propg_delay())),
                        (kv.Operation(kv.Operation.Type.GET,
                                      "k1"),
                         round(5*param.propg_delay()))]

        def next_operation(self):
            if len(self.ops) > 0:
                return self.ops.pop(0)
            else:
                return None, None

    def setUp(self):
        self.stats = kv.KVStats()
        self.simulator = pegasus.simulator.Simulator(self.stats)
        rack = pegasus.node.Rack(0)
        # Single client node and 4 cache nodes all in one rack
        self.client_node = pegasus.node.Node(rack, 0)
        self.cache_nodes = []
        for i in range(4):
            self.cache_nodes.append(pegasus.node.Node(rack, i+1))

        config = self.StaticConfig(self.cache_nodes, None)
        # Register applications
        self.client_app = memcachekv.MemcacheKV(self.SimpleGenerator(),
                                                self.stats)
        self.client_app.register_config(config)
        self.client_node.register_app(self.client_app)

        self.server_apps = []
        for node in self.cache_nodes:
            app = memcachekv.MemcacheKV(None, self.stats)
            app.register_config(config)
            node.register_app(app)
            self.server_apps.append(app)

        self.simulator.add_node(self.client_node)
        self.simulator.add_nodes(self.cache_nodes)

    def test_basic(self):
        self.simulator.run((5+2)*param.MAX_PROPG_DELAY+len(self.SimpleGenerator().ops)*param.MAX_PKT_PROC_LTC)
        self.assertEqual(self.stats.received_replies[kv.Operation.Type.GET],
                         5)
        self.assertEqual(self.stats.received_replies[kv.Operation.Type.PUT],
                         3)
        self.assertEqual(self.stats.received_replies[kv.Operation.Type.DEL],
                         1)
        self.assertEqual(self.stats.cache_hits, 3)
        self.assertEqual(self.stats.cache_misses, 2)
        self.assertEqual(len(self.server_apps[0]._store), 0)
        self.assertEqual(len(self.server_apps[1]._store), 1)
        self.assertTrue(self.server_apps[1]._store["k2"], "v2")
        self.assertEqual(len(self.server_apps[2]._store), 1)
        self.assertTrue(self.server_apps[2]._store["k3"], "v3")
        self.assertEqual(len(self.server_apps[3]._store), 0)
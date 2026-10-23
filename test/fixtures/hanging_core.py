"""A solver that hangs: it reports ready and then never answers - for test/hang_test.dart."""
import json
import sys

print(json.dumps({'jsonrpc': '2.0', 'method': 'ready', 'params': {'version': 'hanging', 'protocol': 1}}), flush=True)
for line in sys.stdin:          # reads the requests, answers nothing - ends when stdin is closed
    pass

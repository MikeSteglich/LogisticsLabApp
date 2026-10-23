"""A solver whose first routing request fails (e.g. a server that does not answer) - for test/routes_test.dart."""
import json
import sys

print(json.dumps({'jsonrpc': '2.0', 'method': 'ready', 'params': {'version': 'flaky', 'protocol': 1}}), flush=True)
calls = 0
for line in sys.stdin:
    msg = json.loads(line)
    if msg.get('method') == 'routing':
        calls += 1
        if calls == 1:
            answer = {'error': {'code': -32000, 'message': 'routing server not available', 'data': {'httpStatus': 503}}}
        else:
            (a, b) = msg['params']['coordinates']
            mid = [(a[0] + b[0]) / 2 + 0.01, (a[1] + b[1]) / 2]
            answer = {'result': {'message': 'ok', 'route': [a, mid, b]}}
    elif msg.get('method') == 'shutdown':
        answer = {'result': {}}
    else:
        answer = {'error': {'code': -32601, 'message': 'unknown method'}}
    print(json.dumps({'jsonrpc': '2.0', 'id': msg.get('id'), **answer}), flush=True)
    if msg.get('method') == 'shutdown':
        break

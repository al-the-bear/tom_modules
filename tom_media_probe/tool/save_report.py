#!/usr/bin/env python3
"""Cuts the report (the PROBE_PART lines) out of a log and writes it as formatted JSON.

    python3 tool/save_report.py <log> <report.json>
"""
import json
import re
import sys


def main() -> int:
    text = open(sys.argv[1], errors='replace').read()
    whole = re.findall(r'PROBE_JSON (\{.*\})', text)
    parts = re.findall(r'PROBE_PART (\d+) (.*)', text)
    if parts:
        # The last run's parts: from the last part 0 on.
        last = max(i for i, (n, _) in enumerate(parts) if n == '0')
        report = json.loads(''.join(chunk for _, chunk in parts[last:]))
    elif whole:
        report = json.loads(whole[-1])
    else:
        print('no report in', sys.argv[1])
        return 1
    with open(sys.argv[2], 'w') as out:
        json.dump(report, out, indent=2)
        out.write('\n')
    print(json.dumps(report, indent=1)[:6000])
    return 0


if __name__ == '__main__':
    sys.exit(main())

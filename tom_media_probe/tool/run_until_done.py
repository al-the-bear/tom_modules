#!/usr/bin/env python3
"""Runs a command, copies its output to a log, and ends it once the probe's
automated run has printed PROBE_DONE (or the time is up).

    python3 tool/run_until_done.py <log> <seconds> <command> [args...]

The report is in the PROBE_PART lines of the log (tool/save_report.py).
"""
import subprocess
import sys
import threading
import time


def main() -> int:
    log_path, limit = sys.argv[1], float(sys.argv[2])
    process = subprocess.Popen(
        sys.argv[3:], stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
        stdin=subprocess.PIPE)
    done = threading.Event()

    def pump() -> None:
        with open(log_path, 'wb') as log:
            for line in process.stdout:
                log.write(line)
                log.flush()
                if b'PROBE_DONE' in line:
                    done.set()

    thread = threading.Thread(target=pump, daemon=True)
    thread.start()
    start = time.time()
    while time.time() - start < limit and not done.is_set():
        if process.poll() is not None:
            break
        time.sleep(0.5)
    time.sleep(1)
    if process.poll() is None:
        try:
            process.stdin.write(b'q')
            process.stdin.flush()
            process.wait(timeout=15)
        except Exception:
            process.kill()
    thread.join(timeout=5)
    print('done' if done.is_set() else 'NOT DONE (time is up or it ended)')
    return 0 if done.is_set() else 1


if __name__ == '__main__':
    sys.exit(main())

# SPDX-License-Identifier: GPL-2.0-or-later
"""A stand-in for xymond_rrd's cache-control socket, for the tests.

    fake-rrdctl.py SOCKET RECORD [DELAY RRD UPDATE]

Binds a Unix datagram socket at SOCKET, as xymond_rrd does at
$XYMONTMP/rrdctl.<pid>, then writes each request it receives -- /HOST/
from showgraph or the API -- to RECORD, one per line, until killed. RECORD
exists, empty, once the socket is bound. With DELAY, RRD and UPDATE, it
answers the first request as xymond_rrd writes a cached value: DELAY
seconds later, rrdtool update RRD UPDATE.
"""
import os
import socket
import subprocess
import sys
import time

path, record = sys.argv[1], sys.argv[2]
write = sys.argv[3:6] if len(sys.argv) >= 6 else None
s = socket.socket(socket.AF_UNIX, socket.SOCK_DGRAM)
s.bind(path)
open(record, "w").close()
try:
    while True:
        msg = s.recv(1024).decode(errors="replace")
        with open(record, "a") as f:
            f.write(msg + "\n")
        if write:
            delay, rrd, update = write
            write = None
            time.sleep(float(delay))
            subprocess.run(["rrdtool", "update", rrd, update], check=False)
finally:
    os.unlink(path)

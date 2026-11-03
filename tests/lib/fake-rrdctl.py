# SPDX-License-Identifier: GPL-2.0-or-later
"""A stand-in for xymond_rrd's cache-control socket, for the tests.

    fake-rrdctl.py SOCKET RECORD

Binds a Unix datagram socket at SOCKET, as xymond_rrd does at
$XYMONTMP/rrdctl.<pid>, then writes each request it receives -- /HOST/
from showgraph or the API -- to RECORD, one per line, until killed. RECORD
exists, empty, once the socket is bound.
"""
import os
import socket
import sys

path, record = sys.argv[1], sys.argv[2]
s = socket.socket(socket.AF_UNIX, socket.SOCK_DGRAM)
s.bind(path)
open(record, "w").close()
try:
    while True:
        msg = s.recv(1024).decode(errors="replace")
        with open(record, "a") as f:
            f.write(msg + "\n")
finally:
    os.unlink(path)

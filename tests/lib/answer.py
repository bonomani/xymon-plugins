# SPDX-License-Identifier: GPL-2.0-or-later
"""Answer a question on a terminal, as a person would.

    answer.py PROMPT ANSWER COMMAND [ARG...]

Runs COMMAND on a pseudo-terminal of its own, waits until it writes PROMPT,
types ANSWER and a newline, and waits for it to end. Prints everything
COMMAND wrote, and exits with its status -- 128 plus the signal when one
killed it. Exits 124 when PROMPT does not come within 60 seconds, or
COMMAND does not end within 120; COMMAND is then killed.
"""
import os
import pty
import select
import signal
import sys
import time

prompt, answer = sys.argv[1].encode(), sys.argv[2].encode()
pid, fd = pty.fork()
if pid == 0:
    os.execvp(sys.argv[3], sys.argv[3:])


def read(until: float) -> bytes:
    got = b""
    while time.time() < until:
        if select.select([fd], [], [], 0.1)[0]:
            try:
                chunk = os.read(fd, 4096)
            except OSError:
                break
            if not chunk:
                break
            got += chunk
    return got


out = b""
deadline = time.time() + 60
while prompt not in out:
    if time.time() > deadline:
        os.kill(pid, signal.SIGKILL)
        sys.stdout.write(out.decode(errors="replace"))
        sys.exit(124)
    out += read(time.time() + 0.2)
os.write(fd, answer + b"\n")
status = None
until = time.time() + 120
while time.time() < until:
    out += read(time.time() + 0.2)
    done, st = os.waitpid(pid, os.WNOHANG)
    if done:
        status = st
        break
out += read(time.time() + 0.2)
sys.stdout.write(out.decode(errors="replace"))
if status is None:
    os.kill(pid, signal.SIGKILL)
    sys.exit(124)
code = os.waitstatus_to_exitcode(status)
sys.exit(code if code >= 0 else 128 - code)

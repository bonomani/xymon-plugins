# SPDX-License-Identifier: GPL-2.0-or-later
"""Read a live Xymon server and map it onto the API's schemas.

The data comes from ``xymondboard``'s structured fields, split on ``|``, with
the colour mapped to a verdict. Status-message bodies are not parsed.

Everything about the server comes from Xymon's own settings, which the
launcher gets from xymonserver.cfg: ``XYMON`` is the xymon client program,
``XYMSRV`` the server to ask, ``XYMONRRDS`` where the RRD files are,
``XYMONSERVERCGIURL`` where showgraph is, and ``XYMONHISTDIR`` and
``XYMONHISTLOGS`` where xymond_history keeps the events and the saved status
texts.
"""
from __future__ import annotations

import base64
import binascii
import hashlib
import json
import os
import re
import socket
import subprocess
import time
import urllib.request
from datetime import datetime, timezone
from urllib.parse import urlencode

XYMON = os.environ.get("XYMON", "xymon")
XYMSRV = os.environ.get("XYMSRV", "")
XYMONRRDS = os.environ.get("XYMONRRDS", "")
XYMONSERVERCGIURL = os.environ.get("XYMONSERVERCGIURL", "").rstrip("/")
XYMONWEBHOST = os.environ.get("XYMONWEBHOST", "").rstrip("/")
XYMONHISTDIR = os.environ.get("XYMONHISTDIR", "")
XYMONHISTLOGS = os.environ.get("XYMONHISTLOGS", "")
# acktime, ackmsg and acklist for a state's acknowledgement; xymondboard
# encodes a "|" inside ackmsg and acklist, so a line still splits on it.
# prevgapcolor (Xymon 4.3.31) is the test's own colour while xymond shows
# another -- purple for a silence, clear for a host down, blue for a
# disable or a DOWNTIME, and any colour a change delay, a flap or a
# modifier puts in place of the one reported (xymond.c: the gap opens
# whenever the colour shown is not the one reported) -- and "none" at every
# other time. disabletime is when a disable ends, -1 until the test is ok
# again, and 0 when none runs; dismsg is a disable's text, or a DOWNTIME's
# cause when no disable runs. logtime is when the status was last updated,
# sender who sent it. line1, the status's first line, is not encoded and
# may hold a "|": it comes last, and a line splits on the fields before it
# only.
BOARD_FIELDS = ["hostname", "testname", "color", "lastchange",
                "acktime", "ackmsg", "acklist", "prevgapcolor", "disabletime",
                "dismsg", "logtime", "sender", "line1"]
# What hosts.cfg says of each host, from xymond's hostinfo, which encodes
# them (xymondboard does not, and a DOWNTIME's cause may hold a "|"):
# dialup, empty without it, and the DOWNTIME tag.
HOST_FIELDS = ["XMH_HOSTNAME", "XMH_FLAG_DIALUP", "XMH_DOWNTIME"]

# A name from the request becomes part of a file path, so it may not hold
# "/" or "..": a path outside XYMONRRDS. A host name never holds ":" either;
# a test name can -- xymond_rrd names an HTTP test's file after its URL,
# tcp.http.www.example.com:8080,.rrd -- and ":" is rrdtool's own separator,
# so it is escaped where the name reaches rrdtool.
_NAME = re.compile(r"[A-Za-z0-9_][A-Za-z0-9_.,-]*")
_TEST = re.compile(r"[A-Za-z0-9_][A-Za-z0-9_.,:-]*")
_DSNAME = re.compile(r"[A-Za-z0-9_]{1,19}")
# Bounded: int() refuses thousands of digits with a ValueError of its own
# (Python 3.11+), and nothing in Xymon is older than 1970 or past 12 digits.
_RELATIVE = re.compile(r"-([0-9]{1,9})([smhdw])")
# [0-9], not str.isdigit(), which also takes "²" -- which int() then refuses.
_DIGITS = re.compile(r"[0-9]{1,12}")
_UNIT = {"s": 1, "m": 60, "h": 3600, "d": 86400, "w": 604800}


class BadRequest(ValueError):
    """A request parameter the API will not pass on: 400."""


class NotFound(LookupError):
    """What was asked for is not there: 404. Not FileNotFoundError, which a
    subprocess raises too when its program is missing -- that is a 502."""


class Upstream(RuntimeError):
    """A failure whose text is this module's own and safe to answer with:
    502. Any other exception is a 502 too, but its text stays in the log."""

# A verdict, never a colour: the colour is how the web pages show it.
COLOUR_STATUS = {"green": "ok", "yellow": "warning", "red": "critical",
                 "blue": "disabled", "clear": "nodata", "purple": "unknown"}
VERDICTS = tuple(dict.fromkeys(COLOUR_STATUS.values()))
# What a test measured, as a severity in ITU-T X.733's words: red critical
# ("immediate corrective action"), yellow warning, green cleared, and
# indeterminate where nothing was measured. Purple, clear and blue are
# xymond's, not the test's: a state keeps the severity last measured, and
# says beside it what xymond added (RFC #113).
COLOUR_SEVERITY = {"red": "critical", "yellow": "warning", "green": "cleared"}
SEVERITIES = ("critical", "warning", "indeterminate", "cleared")
# An alarm's state, as Prometheus and TMF642 name the field: firing and
# suppressed as Alertmanager has them; inactive, Prometheus's word for a rule
# that is not firing, for a green test.
STATES = ("firing", "suppressed", "inactive")
# The flags an alarm may carry, each a filter of /alarms.
FLAGS = ("stale", "unreachable", "suppressed")
# The domain a test lies in, the label that groups alarms (RFC #113): read
# from this table, and the test itself where the table says nothing -- so a
# network service (ssh, smtp, dns) or a script's own test is its own domain.
# ponytail: a fixed table; one an admin can extend when a site asks for it.
DOMAIN = {"cpu": "cpu", "memory": "memory",
          "disk": "filesystem", "inode": "filesystem", "files": "filesystem",
          "msgs": "log", "procs": "process", "svcs": "os-service",
          "ports": "network", "conn": "network",
          "http": "web", "content": "web", "sslcert": "web"}

# xymond_history writes a colour to allevents as its first two letters:
# "gr ye" is green after yellow. The full names are taken too.
_SHORT = {c[:2]: c for c in COLOUR_STATUS}


def _verdict(colour: str) -> str:
    return COLOUR_STATUS.get(_SHORT.get(colour, colour), "unknown")


def query(request: str) -> str:
    """Send one request to xymond and return its answer."""
    out = subprocess.run([XYMON, XYMSRV, request],
                         capture_output=True, text=True, timeout=30)
    if out.returncode != 0:
        raise Upstream(out.stderr.strip() or f"xymon {XYMSRV} failed")
    return out.stdout


def ping() -> str:
    """xymond's answer to a ping: its name and version."""
    return query("ping").strip()


def _rows() -> list[dict]:
    board = query(f"xymondboard fields={','.join(BOARD_FIELDS)}")
    return [dict(zip(BOARD_FIELDS, line.split("|", len(BOARD_FIELDS) - 1)))
            for line in board.splitlines() if line.strip()]


def _hosts_cfg() -> dict[str, dict]:
    """HOST_FIELDS for each host, by name."""
    out = {}
    for line in query(f"hostinfo fields={','.join(HOST_FIELDS)}").splitlines():
        f = [_nldecode(v) for v in line.split("|")]
        if len(f) == len(HOST_FIELDS):
            out[f[0]] = dict(zip(HOST_FIELDS, f))
    return out


def _iso(epoch: str) -> str | None:
    """EPOCH as an ISO time; None for none, xymond's 0 among them -- a test
    such as trends that never changed, not a change in 1970."""
    try:
        n = int(epoch)
        return datetime.fromtimestamp(n, timezone.utc).isoformat().replace("+00:00", "Z") if n > 0 else None
    except (ValueError, TypeError, OSError, OverflowError):
        return None


def alarms(host: str | None = None, test: str | None = None,
           severity: str | None = None, state: str | None = None,
           **flags: str | None) -> list[dict]:
    """One Alarm per host and test on the board, green ones too, as TMF642
    keeps a cleared alarm -- one per object, where its status names them --
    with the severity it last measured, its state, and, beside it,
    what xymond added: stale for a test gone silent (purple), unreachable
    for one made clear because its host's conn is not green (reportedBy that
    conn's state), suppressed for one disabled or in a DOWNTIME window
    (blue), with suppressedBy saying which, until when, by whom and why,
    where Xymon keeps it. Filtered on each argument given; a flag's filter
    is true or false."""
    # A value outside the contract's list matches nothing: refused, not an
    # empty board -- "severity=red", a colour where a severity is asked,
    # would read as "nothing is red" (#92). An empty one is refused too: it
    # would read as no filter, the whole board.
    for name, value in (("host", host), ("test", test), ("severity", severity), ("state", state)):
        if value == "":
            raise BadRequest(f"{name} is empty")
    if severity and severity not in SEVERITIES:
        raise BadRequest(f"severity must be one of {', '.join(SEVERITIES)}, not a colour")
    if state and state not in STATES:
        raise BadRequest(f"state must be one of {', '.join(STATES)}")
    for flag, value in flags.items():
        if value is not None and value not in ("true", "false"):
            raise BadRequest(f"{flag} must be true or false")
    out = [st for st in _states()
           if (not host or st["host"] == host) and (not test or st["test"] == test)
           and (not severity or st["severity"] == severity)
           and (not state or st["state"] == state)]
    for flag, value in flags.items():
        if value is not None:
            key = "suppressedBy" if flag == "suppressed" else flag
            out = [st for st in out if (key in st) == (value == "true")]
    return out


_ID = re.compile(r"[0-9a-f]{16}")


def alarm(alarm_id: str) -> dict:
    """The Alarm ALARM_ID, with its status's text: what the web page shows."""
    if not _ID.fullmatch(alarm_id):
        raise NotFound(f"no alarm {alarm_id}")
    for a in alarms():
        if a["id"] == alarm_id:
            return {**a, "text": _status_text(a["host"], a["test"])}
    raise NotFound(f"no alarm {alarm_id}")


def _states() -> list[dict]:
    res: list[dict] = []
    now = int(time.time())
    rows = _rows()
    hosts = _hosts_cfg()
    # xymond makes a silent test clear, not purple, when its host's conn is
    # not green (xymond.c, "go CLEAR, instead of PURPLE"), and xymonnet its
    # network tests when the conn fails: that conn is what says the host
    # cannot be reached. A dialup host's tests go clear because it is one,
    # nothing failed: not unreachable.
    conn = {d.get("hostname"): d.get("color") for d in rows if d.get("testname") == "conn"}
    ends: dict[tuple[str, str], int | None] = {}
    for d in rows:
        colour = d.get("color", "clear")
        host, tst = d.get("hostname", "?"), d.get("testname", "?")
        cfg = hosts.get(host, {})
        # The colour the test reported, where xymond shows another: a gap is
        # open, its colour in prevgapcolor. Otherwise the one shown is it.
        gap = d.get("prevgapcolor", "none") not in ("", "none")
        own = d["prevgapcolor"] if gap else colour
        a = {"host": host, "test": tst,
             "domain": DOMAIN.get(tst, tst),
             "severity": COLOUR_SEVERITY.get(own, "indeterminate"),
             "state": {"blue": "suppressed", "green": "inactive"}.get(colour, "firing")}
        t = _iso(d.get("lastchange", ""))
        if t:
            a["since"] = t
        if colour == "purple" and gap:
            # xymond's purple, the test gone silent; a purple a client sent
            # itself is a report, not a silence.
            a["stale"] = {"since": t}
        elif (colour == "clear" and tst != "conn" and not cfg.get("XMH_FLAG_DIALUP")
              and conn.get(host, "green") in ("red", "yellow", "blue", "clear")):
            a["unreachable"] = {"reportedBy": [_state_id({"host": host, "test": "conn"})]}
        elif colour == "blue":
            by = _suppressed_by(d, cfg.get("XMH_DOWNTIME", ""), tst, own, now, ends)
            if by:
                a["suppressedBy"] = by
        updated = _iso(d.get("logtime", ""))
        if updated:
            a["updated"] = updated
        if d.get("sender"):
            a["source"] = d["sender"]
        message = _message(d.get("line1", ""))
        if message:
            a["message"] = message
        ack = _acknowledgement(d, now)
        if ack:
            # Xymon acknowledges a test, all it holds: say so, for the day
            # one instance is acknowledged on its own (RFC #113).
            a["acknowledged"] = {**ack, "of": "test"}
        res += _instances(a) if tst in _INSTANCE_TESTS and a["severity"] != "cleared" else [a]
    out = []
    for a in res:
        i = _state_id(a)
        out.append({"id": i, **a, "link": f"alarms/{i}"})
    return out


def _suppressed_by(d: dict, downtime: str, tst: str, own: str, now: int,
                   ends: dict[tuple[str, str], int | None]) -> list[dict]:
    """What suppresses a blue test, one entry each, a field Xymon does not
    keep left out: a disable (disabletime set), with its end and words; a
    DOWNTIME, with its end and its cause. xymond keeps that cause in dismsg
    when no disable runs, and only then: a dismsg with no disable is a
    DOWNTIME's. Under a disable, a DOWNTIME window of hosts.cfg holding the
    test now over a red, yellow or purple report -- the only ones xymond
    applies it to -- is one too. A blue the test reported itself has
    neither: nothing is said of why."""
    by = []
    until = d.get("disabletime", "0")
    disabled = until not in ("", "0")
    if disabled:
        entry = {"kind": "disable", "of": "test"}
        if until != "-1" and _iso(until):
            entry["until"] = _iso(until)
        entry.update(_disable_words(d.get("dismsg", "")))
        by.append(entry)
    cause = "" if disabled else hide(_nldecode(d.get("dismsg", ""))).strip()
    if cause or (downtime and own in ("red", "yellow", "purple") and
                 _downtime_holds(downtime, tst, time.localtime(now - now % 60))):
        entry = {"kind": "downtime", "of": "test"}
        key = (downtime, tst)
        if key not in ends:
            ends[key] = _downtime_until(downtime, tst, now)
        if ends[key]:
            entry["until"] = _iso(str(ends[key]))
        if cause:
            entry["text"] = cause
        by.append(entry)
    return by


def _downtime_until(spec: str, test: str, now: int) -> int | None:
    """When the DOWNTIME window SPEC holding TEST at NOW ends: the first
    minute xymond no longer finds TEST in it, as check_downtime and
    within_sla read it (xymond.c, timefunc.c), in this machine's local
    time, which is xymond's. None when it does not hold TEST now, or holds
    it for the week ahead and more -- a window that never ends. Holidays
    play no part: xymond never loads holidays.cfg (only xymond_alert and
    the info page do), whatever hosts.cfg(5) says.
    ponytail: a minute at a time over 8 days, 11520 steps; fine per blue test."""
    start = now - now % 60
    if not _downtime_holds(spec, test, time.localtime(start)):
        return None
    for t in range(start + 60, start + 8 * 86400, 60):
        if not _downtime_holds(spec, test, time.localtime(t)):
            return t
    return None


def _downtime_holds(spec: str, test: str, t: time.struct_time) -> bool:
    """Whether xymond's check_downtime finds TEST in the DOWNTIME SPEC at T:
    entries "DAYS:START:END" (every test) or "TESTS:DAYS:START:END:CAUSE",
    split as xymond splits them."""
    def cut(p: str, stops: str) -> tuple[str, str, str]:
        i = next((n for n, c in enumerate(p) if c in stops), len(p))
        return p[:i], p[i:i + 1], p[i + 1:]
    p = spec
    while p:
        s1, _, p = cut(p, ":")
        s2, _, p = cut(p, ":")
        s3, stop, p = cut(p, ":;,")
        if stop == ":":
            s4, _, p = cut(p, ":")
            _, _, p = cut(p, ",;")
            timetxt, tests = f"{s2}:{s3}:{s4}", s1
        else:
            timetxt, tests = f"{s1}:{s2}:{s3}", "*"
        if _within_sla(timetxt, t) and (tests == "*" or test in tests.split(",")):
            return True
    return False


def _within_sla(timespec: str, t: time.struct_time) -> bool:
    """xymond's within_sla as xymond runs it, holidays never loaded:
    "DAYS:HHMM:HHMM[,...]", DAYS of
    * (every day), W (Monday to Friday), 0 to 6 (Sunday to Saturday); start
    and end both inside, an end before the start crossing midnight."""
    def minutes(p: str) -> int:
        return int(p[:2]) * 60 + int(p[2:4]) if len(p) >= 4 and p[:4].isdigit() else 0
    wday, now = (t.tm_wday + 1) % 7, t.tm_hour * 60 + t.tm_min
    for one in timespec.split(","):
        days, _, times = one.partition(":")
        match = False
        for c in days:
            if c == "*" or (c in "Ww" and 1 <= wday <= 5) or c == str(wday):
                match = True
                break
            if c not in "0123456Ww":
                break
        begin, sep, end = times.partition(":")
        if match and sep:
            b, e = minutes(begin), minutes(end)
            if (b <= now <= e) if e > b else (now >= b or now <= e):
                return True
    return False


def _state_id(a: dict) -> str:
    """A state's id: opaque, the same while its host, test and instance are
    (RFC #113: not composed from the levels, which an instance's ":" would
    make ambiguous)."""
    key = "\0".join((a["host"], a["test"], a.get("instance", "")))
    return hashlib.sha256(key.encode()).hexdigest()[:16]


# The tests whose status names each object it judged: xymond writes inode's
# lines in alarm as "&red <!-- ID=/var --> ..." (xymond_client.c), the only
# ones with ID=. disk writes the same lines without it, so its file systems
# are left in the message until Xymon names them (RFC #113, step 5).
_INSTANCE_TESTS = {"inode"}
_ID_LINE = re.compile(r"^&(red|yellow) <!-- ID=(.+?) -->\s*(.*)$", re.M)
# "/var (95% used) has reached the PANIC level (90%)"; a limit in units free
# instead of a percentage gives no pct, and is left in the message.
_PCT = re.compile(r"\((\d+)% used\) has reached the (PANIC|WARNING) level \((\d+)%\)")


def _instances(alarm: dict) -> list[dict]:
    """ALARM, one per object its status names in alarm, each with its
    instance, the severity of its own line and, where the line gives them,
    its pct and the threshold it crossed. ALARM itself when none is named."""
    board = query(f"xymondboard host=^{re.escape(alarm['host'])}$ "
                  f"test=^{re.escape(alarm['test'])}$ fields=msg")
    out = []
    for colour, name, words in _ID_LINE.findall(_nldecode(board)):
        # The line's colour is what the test measured of that object when it
        # last reported, whatever xymond shows over it since.
        a = {**alarm, "instance": name, "severity": COLOUR_SEVERITY[colour],
             "message": hide(words.strip()[:_MESSAGE_MAX])}
        m = _PCT.search(words)
        if m:
            level = "critical" if m.group(2) == "PANIC" else "warning"
            a["metric"] = "pct"
            a["measure"] = {"value": int(m.group(1)), "unit": "%", level: int(m.group(3))}
        elif "is unreachable (not measured)" in words:
            a["measure"] = {"state": "unreachable"}
        out.append(a)
    return out or [alarm]


# A status's first line as line1 gives it: its colour, then xymond's flags
# comment, then the words the test wrote.
_LINE1_HEAD = re.compile(r"\A\S+\s*(?:<!--\s*\[flags:[^\]]*\]\s*-->\s*)?")
_MESSAGE_MAX = 200
# The date most statuses open with, as the client and xymonnet write it --
# "Thu Nov 19 18:56:26 2026:", "Thu Nov 19 18:56:26 CET 2026 -" -- which
# updated already gives: left out of the message.
_LINE1_DATE = re.compile(r"\A[A-Z][a-z]{2} [A-Z][a-z]{2} +[0-9]{1,2} [0-9]{2}:[0-9]{2}:[0-9]{2}"
                         r"(?: [A-Z]{2,5})? [0-9]{4}(?:\s*[:-])?\s*")


def _message(line1: str) -> str:
    """The words of a status's first line, without its colour or the date
    it opens with, hidden as the status text is, at most _MESSAGE_MAX
    characters."""
    words = _LINE1_HEAD.sub("", line1, count=1).strip()
    return hide(_LINE1_DATE.sub("", words, count=1).strip()[:_MESSAGE_MAX])


def hosts() -> list[dict]:
    """Each host on the board, once."""
    return [{"host": h} for h in dict.fromkeys(d.get("hostname", "?") for d in _rows())]


_STATUS_FIELDS = ["hostname", "testname", "msg"]
_STATUS_MAX = 1024 * 1024

# XYMONAPI_HIDE names a file of regular expressions, one per line; what they
# match is replaced by [hidden] in every text the API returns -- a status,
# an acknowledgement, a saved status -- so that a password typed on a
# command line and caught in a process list does not travel further than
# the web page it is already on. Read once, at start.
HIDE_FILE = os.environ.get("XYMONAPI_HIDE", "")
HIDDEN = "[hidden]"
_hide: list[re.Pattern] = []


def load_hide() -> int:
    """Compile XYMONAPI_HIDE; the number of expressions. Raises ValueError,
    with the line, for one that is not a regular expression, and OSError for
    a file that cannot be read: the API then refuses to start, rather than
    run without the hiding it was asked for."""
    _hide.clear()
    if not HIDE_FILE:
        return 0
    with open(HIDE_FILE, encoding="utf-8") as fd:
        for n, line in enumerate(fd, 1):
            line = line.rstrip("\n")
            if not line.strip() or line.lstrip().startswith("#"):
                continue
            try:
                _hide.append(re.compile(line))
            except re.error as e:
                raise ValueError(f"{HIDE_FILE} line {n}: {e}") from e
    return len(_hide)


def hide(text: str) -> str:
    for rx in _hide:
        text = rx.sub(HIDDEN, text)
    return text
# The command that set the status: "status", with a lifetime ("+5h") or a
# group ("/group:web") or both, then HOST.TEST, then the colour, then xymond's
# flags comment.
_STATUS_HEAD = re.compile(r"\Astatus\S*\s+\S+\s+\S+\s*(?:<!--\s*\[flags:[^\]]*\]\s*-->\s*)?")
# xymondboard writes msg, ackmsg and dismsg through nlencode (lib/encoding.c):
# "|" as \p, newline \n, carriage return \r, tab \t, and a backslash \\.
_NL = {"p": "|", "n": "\n", "r": "\r", "t": "\t", "\\": "\\"}
_NLESC = re.compile(r"\\(.)", re.S)


def _nldecode(text: str) -> str:
    return _NLESC.sub(lambda m: _NL.get(m.group(1), m.group(0)), text)


def _acknowledgement(d: dict, now: int) -> dict | None:
    """The acknowledgement running on a board line, as /alarms
    gives it -- {"until", "text"}, and "since" when xymond kept its
    start -- or None.

    xymond clears an acknowledgement that ran out only when the next status
    arrives; until then the board still carries it, and its XML output too
    reports it only while acktime is ahead of now. Two ways to acknowledge:
    xymondack sets acktime and ackmsg; the critical-systems view's ackinfo
    adds to acklist, one "start:until:level:by:text" line each, acktime left
    at 0. Xymon's pages show either (xymongen/loaddata.c); the one running
    longest is given. xymondack keeps no start (xymond.c: acktime is now
    plus its duration); an acklist line does, its first field.

    An acklist line's text is given as "by:text", whole: neither field is
    escaped, so a "by" holding a ":" -- dom:alice -- cannot be told from the
    text, and splitting it would cut the words wrongly (#89)."""
    acks = []
    acktime = d.get("acktime", "")
    if _DIGITS.fullmatch(acktime) and int(acktime) > now:
        acks.append((int(acktime), _nldecode(d.get("ackmsg", "")), ""))
    for line in _nldecode(d.get("acklist", "")).splitlines():
        a = line.split(":", 3)
        if len(a) == 4 and _DIGITS.fullmatch(a[1]) and int(a[1]) > now:
            acks.append((int(a[1]), a[3], a[0]))
    if not acks:
        return None
    until, words, start = max(acks)
    ack = {"until": _iso(str(until))}
    since = _iso(start)
    if since:
        ack["since"] = since
    # The web page's acknowledgement ends its words with who made it, and
    # from where (web/acknowledge.c), which Xymon's own feed reads back
    # (web/appfeed.c, AckedBy): read here too. An acklist line's who is not split
    # from its words, above.
    m = _ACKED_BY.match(words) if not start else None
    if m:
        ack["ackedBy"] = hide(m[2].strip())
        if m[3]:
            ack["from"] = hide(m[3])
        words = m[1]
    ack["text"] = hide(words.strip())
    return ack


# "WORDS \nAcked by: USER (ADDR)", the address there when the web server
# gave one.
_ACKED_BY = re.compile(r"\A(.*?)\s*\nAcked by: (.+?)(?: \((\S+)\))?[ \t]*\n?\Z", re.S)


def _status_text(host: str, tst: str) -> str:
    """The text of HOST's TEST status, as the web page shows it."""
    # xymondboard reads host= and test= as regular expressions, unanchored:
    # host=web1 also finds web10, and "." is any character. The names are
    # anchored and escaped, and the line is checked to be the one asked for.
    board = query(f"xymondboard host=^{re.escape(host)}$ test=^{re.escape(tst)}$"
                  f" fields={','.join(_STATUS_FIELDS)}")
    for line in board.splitlines():
        # msg is last; every "|" inside the texts is encoded, so the split
        # lands on the field boundaries.
        f = line.split("|", len(_STATUS_FIELDS) - 1)
        if len(f) == len(_STATUS_FIELDS) and f[0] == host and f[1] == tst:
            # The text begins with the command that set it, "status+30
            # host,example,com.conn red", and xymond's flags comment, which
            # the web page does not show either.
            msg = dict(zip(_STATUS_FIELDS, f))["msg"]
            return hide(_STATUS_HEAD.sub("", _nldecode(msg), count=1)[:_STATUS_MAX])
    raise NotFound(f"no status for {host} {tst}")


# The text the web page gives a disable (web/enadis.c): a fixed form of
# Xymon's own, which a disable sent with xymon(1) does not have.
_DISABLED_BY = re.compile(r"\A\s*Disabled by: (.*?) @ (\S+)[ \t]*\nReason: (.*)\Z", re.S)


def _disable_words(dismsg: str) -> dict:
    """A disable's text, encoded as the board gives it: its reason, and who
    set it from which address when the web page did (createdBy, as
    Alertmanager's silence has it, and from);
    the text whole otherwise. Each hidden as the status text is; what is
    empty is left out."""
    text = _nldecode(dismsg)
    m = _DISABLED_BY.match(text)
    words = {"createdBy": m[1], "from": m[2], "text": m[3]} if m else {"text": text}
    return {k: hide(v.strip()) for k, v in words.items() if v.strip()}


def _name(value: str | None, what: str) -> str:
    rx = _TEST if what == "test" else _NAME
    if not value or not rx.fullmatch(value) or ".." in value:
        raise BadRequest(f"{what} must be a Xymon host or test name")
    return value


def epoch(value: str, now: int | None = None) -> int:
    """'now', seconds since the epoch, or a relative time such as -24h."""
    now = int(time.time()) if now is None else now
    if value == "now":
        return now
    if _DIGITS.fullmatch(value):
        return int(value)
    m = _RELATIVE.fullmatch(value)
    if m:
        return now - int(m.group(1)) * _UNIT[m.group(2)]
    raise BadRequest(f"time '{value}' must be now, seconds since the epoch, or like -24h")


def _flush(host: str) -> bool:
    """Ask xymond_rrd to write HOST's cached updates now, as showgraph does
    before drawing a graph: the text /HOST/ to each of its control sockets,
    rrdctl.<pid> in XYMONTMP -- in XYMONRUNDIR too, where a newer Xymon puts
    them. True when one took the request. It only makes an answer fresher: a
    directory missing, a left-over file nobody listens on, a send refused or
    a path too long for a socket, and the file is read as it stands."""
    req = f"/{host}/".encode()
    dirs = {d for d in (os.environ.get("XYMONTMP", ""), os.environ.get("XYMONRUNDIR", "")) if d}
    sent = False
    with socket.socket(socket.AF_UNIX, socket.SOCK_DGRAM) as s:
        s.setblocking(False)
        for d in dirs:
            try:
                names = os.listdir(d)
            except OSError:
                continue
            for n in names:
                if n.startswith("rrdctl."):
                    try:
                        s.sendto(req, os.path.join(d, n))
                        sent = True
                    except OSError:
                        pass
    return sent


# xymond_rrd holds updates for up to 30 minutes before writing them: a range
# that ends earlier than that is on disk already, and needs no flush.
CACHE_SECONDS = 1800


# How long, at most, to wait for xymond_rrd to write a host's cached updates
# once asked: until the file's last update moves, read every _FLUSH_POLL.
# showgraph waits a fixed 0.3 s; on a Xymon that serves the request at once
# the file moves sooner, on one that serves it late the answer says so in
# its updated (#128, xymon-monitoring/xymon#911).
_FLUSH_WAIT = 1.0
_FLUSH_POLL = 0.1
_DSINFO = re.compile(r"^ds\[([^\]]+)\]\.index = ", re.M)
_LASTUPDATE = re.compile(r"^last_update = ([0-9]+)$", re.M)


def _info(rrd: str) -> str:
    out = subprocess.run(["rrdtool", "info", rrd], capture_output=True, text=True, timeout=30)
    if out.returncode != 0:
        raise Upstream(out.stderr.strip() or "rrdtool info failed")
    return out.stdout


def _last_update(info: str) -> int | None:
    m = _LASTUPDATE.search(info)
    return int(m.group(1)) if m else None


def _dataset(info: str, host: str, tst: str) -> str:
    """The dataset to read when none is named: the file's only one -- la in
    la.rrd, sec in a tcp.*.rrd, as most of Xymon's files hold one -- else
    lambda when it is among several, the default before there was a choice;
    else none can be picked for the caller, who is told the names."""
    names = _DSINFO.findall(info)
    if len(names) == 1:
        return names[0]
    if "lambda" in names:
        return "lambda"
    raise BadRequest(f"metric is needed: {tst}.rrd of {host} holds {', '.join(names) or 'no dataset'}")


def series(host: str | None, test: str | None, metric: str | None,
           frm: str, to: str) -> dict:
    """The values of one dataset of HOST/TEST.rrd over a time range."""
    host, tst = _name(host, "host"), _name(test, "test")
    if metric and not _DSNAME.fullmatch(metric):
        raise BadRequest("metric must be an RRD dataset name")
    start, end = epoch(frm), epoch(to)
    if start > end:
        raise BadRequest("from must not be after to")
    if not XYMONRRDS:
        raise Upstream("XYMONRRDS is not set")
    rrd = os.path.join(XYMONRRDS, host, f"{tst}.rrd")
    if not os.path.isfile(rrd):
        raise NotFound(f"no RRD file for {host} {tst}")
    info = _info(rrd)
    ds = metric or _dataset(info, host, tst)
    last = _last_update(info)
    if end >= time.time() - CACHE_SECONDS and _flush(host):
        # Waited for until the file moves, at most _FLUSH_WAIT: a host with
        # nothing cached leaves it as it is, and costs the whole wait.
        deadline = time.monotonic() + _FLUSH_WAIT
        while time.monotonic() < deadline:
            time.sleep(_FLUSH_POLL)
            now_last = _last_update(_info(rrd))
            if now_last != last:
                last = now_last
                break
    # xport keeps to 400 rows unless told otherwise (--maxrows), so a span of
    # years comes back consolidated, not as every step: the answer is bounded.
    out = subprocess.run(["rrdtool", "xport", "--json", "--start", str(start),
                          "--end", str(end), f"DEF:v={rrd.replace(':', chr(92) + ':')}:{ds}:AVERAGE",
                          "XPORT:v:v"],
                         capture_output=True, text=True, timeout=30)
    if out.returncode != 0:
        err = out.stderr.strip()
        if "No DS called" in err:         # rrdtool's words for a dataset the file has not
            raise NotFound(f"no dataset {ds} in {tst}.rrd of {host}")
        raise Upstream(err or "rrdtool xport failed")
    doc = json.loads(out.stdout)
    meta = doc.get("meta", {})
    first, step = int(meta.get("start", 0)), int(meta.get("step", 1) or 1)
    points = [{"t": _iso(str(first + i * step)), "v": row[0] if row else None}
              for i, row in enumerate(doc.get("data", []))]
    # When the file last received a value: the client judges how fresh the
    # points are, against now or an alarm's updated.
    return {"labels": {"host": host, "test": tst}, "metric": ds,
            "updated": _iso(str(last)) if last is not None else None,
            "points": points}


def graph(host: str | None, test: str | None, frm: str, to: str) -> bytes:
    """The PNG graph showgraph draws for HOST and TEST over a time range."""
    q = urlencode({"host": _name(host, "host"), "service": _name(test, "test"),
                   "graph_start": epoch(frm), "graph_end": epoch(to),
                   "action": "view"})
    if not XYMONSERVERCGIURL:
        raise Upstream("XYMONSERVERCGIURL is not set")
    # xymonserver.cfg gives XYMONSERVERCGIURL as a path, "/xymon-cgi": the
    # web pages use it relative to themselves. A URL needs the host, which
    # XYMONWEBHOST holds ("http://www.foo.com"), as Xymon's own pages do.
    url = XYMONSERVERCGIURL
    if "://" not in url:
        if not XYMONWEBHOST:
            raise Upstream("XYMONSERVERCGIURL is a path and XYMONWEBHOST is not set")
        url = XYMONWEBHOST.rstrip("/") + "/" + url.lstrip("/")
    with urllib.request.urlopen(f"{url}/showgraph.sh?{q}", timeout=30) as r:
        png = r.read(_GRAPH_MAX + 1)
    # What came back is served as a PNG, so it must be one: showgraph.cgi
    # answers an error as HTML, with status 200.
    if not png.startswith(_PNG):
        raise Upstream(f"showgraph.sh at {url} did not answer with a PNG")
    if len(png) > _GRAPH_MAX:
        raise Upstream(f"showgraph.sh at {url} answered more than {_GRAPH_MAX} bytes")
    return png



_PNG = b"\x89PNG\r\n\x1a\n"
_GRAPH_MAX = 8 * 1024 * 1024


# --- History -------------------------------------------------------------------
# xymond_history writes one line to $XYMONHISTDIR/allevents per colour change
# -- "host test time prevtime prevduration newcolour oldcolour trend" -- and
# saves the status text of each change as
# $XYMONHISTLOGS/<host, dots as underscores>/<test>/<time>, the time in local
# time as Fri_Nov_7_16:01:08_2002 (lib/timefunc.c, histlogtime()).
_HISTLOG_MAX = 1024 * 1024


def _lines_from_end(path: str, block: int = 65536):
    """The lines of a file, last first, read in blocks from its end: allevents
    grows for years, and the newest changes are at its end."""
    with open(path, "rb") as fd:
        fd.seek(0, os.SEEK_END)
        pos = fd.tell()
        rest = b""
        while pos > 0:
            size = min(block, pos)
            pos -= size
            fd.seek(pos)
            chunk = fd.read(size) + rest
            lines = chunk.split(b"\n")
            rest = lines[0]              # cut by the block boundary, or the file's first line
            for line in reversed(lines[1:]):
                yield line.decode("utf-8", errors="replace")
        if rest:
            yield rest.decode("utf-8", errors="replace")


def events(host: str | None, test: str | None, since: str | None,
           limit: str | None, before: str | None = None) -> list[dict]:
    """The colour changes in allevents, the newest first. BEFORE, seconds
    since the epoch, keeps to the changes older than that: the epoch of the
    last change of one answer gives the next, and so a history longer than
    1000 changes is read page by page."""
    host = _name(host, "host") if host else None
    tst = _name(test, "test") if test else None
    start = epoch(since) if since else 0
    if before is not None and not _DIGITS.fullmatch(before):
        raise BadRequest("before must be seconds since the epoch")
    end = int(before) if before else None
    try:
        n = int(limit) if limit else 100
    except ValueError:
        n = 0
    if not 1 <= n <= 1000:
        raise BadRequest("limit must be a number from 1 to 1000")
    if not XYMONHISTDIR:
        raise Upstream("XYMONHISTDIR is not set")
    # The directory must be there; only allevents may not be yet. A missing
    # directory is a wrong setting, and an empty history would hide it.
    if not os.path.isdir(XYMONHISTDIR):
        raise Upstream(f"XYMONHISTDIR={XYMONHISTDIR} is not a directory")
    path = os.path.join(XYMONHISTDIR, "allevents")
    if not os.path.isfile(path):
        return []                       # nothing has changed colour yet
    # From the end, so the newest N cost the same whatever the file's length;
    # xymond_history appends in time order, so a line older than SINCE ends it.
    found: list[list[str]] = []
    for line in _lines_from_end(path):
        f = line.split()
        if len(f) < 7 or not _DIGITS.fullmatch(f[2]):
            continue
        t = int(f[2])
        if t < start:
            break
        if end is not None and t >= end:
            continue
        if (host and f[0] != host) or (tst and f[1] != tst):
            continue
        found.append(f)
        if len(found) == n:
            break
    return [{"host": f[0], "test": f[1], "time": _iso(f[2]), "epoch": int(f[2]),
             "verdict": _verdict(f[5]),
             "previous": _verdict(f[6]),
             "previous_duration": int(f[4]) if _DIGITS.fullmatch(f[4]) else None}
            for f in found]


def histlog(host: str | None, test: str | None, when: str | None) -> dict:
    """The status text xymond_history saved when HOST's TEST changed colour
    at WHEN, seconds since the epoch as /events gives it."""
    host, tst = _name(host, "host"), _name(test, "test")
    if not when or not _DIGITS.fullmatch(when):
        raise BadRequest("time must be seconds since the epoch")
    if not XYMONHISTLOGS:
        raise Upstream("XYMONHISTLOGS is not set")
    try:
        t = time.localtime(int(when))
    except (OverflowError, OSError, ValueError) as e:
        raise BadRequest(f"time {when} is out of range") from e
    name = time.strftime(f"%a_%b_{t.tm_mday}_%H:%M:%S_%Y", t)
    path = os.path.join(XYMONHISTLOGS, host.replace(".", "_"), tst, name)
    if not os.path.isfile(path):
        raise NotFound(f"no saved status for {host} {tst} at {when}")
    # Bytes, then text: the limit is on what is read from disk, 1 MiB, not on
    # characters, of which 1 MiB could be four times as much.
    with open(path, "rb") as fd:
        text = fd.read(_HISTLOG_MAX).decode("utf-8", errors="replace")
    return {"host": host, "test": tst, "time": _iso(when), "text": hide(text)}

# --- HTTP Basic authentication -----------------------------------------------
# The users are the web pages' own: the htpasswd file useradm and chpasswd
# keep with Apache's htpasswd. That program checks the password too, so every
# format it writes is understood here without a hashing library: $apr1$ by
# default, bcrypt, SHA. The password goes on its stdin, never its command line.
# Xymon's own password file, the one its web pages and useradm.cgi use, is
# the default: the API then asks for what the pages ask for. When it is
# missing the API does not start, rather than answer anyone: an API open to
# anyone who reaches it is asked for, with XYMONAPI_PASSWD set to the empty
# string, never had by a file that went missing.
XYMONPASSWD_DEFAULT = os.path.join(os.environ.get("XYMONHOME", "/nonexistent"), "etc", "xymonpasswd")
XYMONAPI_PASSWD = os.environ.get("XYMONAPI_PASSWD", XYMONPASSWD_DEFAULT)
_USER = re.compile(r"[^\s:-][^\s:]*")


def parse_basic(header: str | None) -> tuple[str, str] | None:
    """(user, password) from an Authorization: Basic header, or None."""
    # The scheme is case-insensitive (RFC 7235): "basic" is sent too.
    if not header or header[:6].lower() != "basic ":
        return None
    try:
        user, _, password = base64.b64decode(header[6:], validate=True) \
            .decode("utf-8").partition(":")
    except (binascii.Error, UnicodeDecodeError):
        return None
    return user, password


# The users of the file, read again only when it changes: a token's owner is
# looked up here on every request, so that removing a user from the file
# ends their machines' access as it ends their password's.
_users: tuple[tuple[float, int], frozenset[str]] | None = None


def has_user(user: str) -> bool | None:
    """Whether XYMONAPI_PASSWD names USER, whatever the password; None when
    the file cannot be read, which says nothing of USER: a token is then
    refused, but not revoked."""
    global _users
    try:
        st = os.stat(XYMONAPI_PASSWD)
        if _users and _users[0] == (st.st_mtime, st.st_size):
            return user in _users[1]
        with open(XYMONAPI_PASSWD, encoding="utf-8", errors="replace") as fd:
            names = frozenset(line.split(":", 1)[0] for line in fd if ":" in line)
    except OSError:
        return None
    _users = ((st.st_mtime, st.st_size), names)
    return user in names


def verify_basic(user: str, password: str) -> bool:
    """Whether XYMONAPI_PASSWD holds this user with this password."""
    # A user name is an argument to htpasswd, so it may not look like an
    # option; a newline would end the password htpasswd reads.
    if not _USER.fullmatch(user) or "\n" in password or "\r" in password:
        return False
    try:
        out = subprocess.run(["htpasswd", "-v", "-i", XYMONAPI_PASSWD, user],
                             input=password, capture_output=True, text=True,
                             timeout=10)
    except (OSError, subprocess.TimeoutExpired):
        return False
    return out.returncode == 0

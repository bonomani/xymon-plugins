# SPDX-License-Identifier: GPL-2.0-or-later
"""A client for xymonapi(8), with nothing but the standard library: the MCP
server and the search in xymonapi-rag/ both read the API through it.

XYMONAPI_URL is where the API is, http://127.0.0.1:1986 by default.
XYMONAPI_TOKEN_FILE names a file holding a client token -- the one the setup
script /client writes keeps -- sent when the API asks for a user: the token
is this machine's own, revoked on its own (xymonapi(8), TOKENS). It is the
only credential sent: a password is never kept here. XYMONAPI_TOKEN is the
token itself, for a test or a one-off.
XYMONAPI_CA names the certificate, or the CA, to trust for an https:// URL
when it is not one the system trusts already: xymond's own, from
xymon-tls(7), which the API uses too.
"""
from __future__ import annotations

import json
import os
import secrets
import re
import ssl
import sys
import urllib.error
import urllib.request
from urllib.parse import urlencode, urlsplit

URL = os.environ.get("XYMONAPI_URL", "http://127.0.0.1:1986").rstrip("/")
CA = os.environ.get("XYMONAPI_CA", "")
TOKEN = os.environ.get("XYMONAPI_TOKEN", "")
TOKEN_FILE = os.environ.get("XYMONAPI_TOKEN_FILE", "")


def _token() -> str:
    """XYMONAPI_TOKEN, or the first line of XYMONAPI_TOKEN_FILE, or ""."""
    if TOKEN or not TOKEN_FILE:
        return TOKEN
    try:
        with open(TOKEN_FILE, encoding="utf-8") as fd:
            return fd.readline().strip()
    except OSError as e:
        raise APIError(f"cannot read XYMONAPI_TOKEN_FILE={TOKEN_FILE}: {e.strerror}") from e


class APIError(RuntimeError):
    """The API could not be reached, or refused the request; the text says which.
    status is the HTTP status of a refusal, None when there was no answer."""

    def __init__(self, message: str, status: int | None = None):
        super().__init__(message)
        self.status = status


class _NoRedirect(urllib.request.HTTPRedirectHandler):
    # urllib follows a redirect with every header but the content ones, so the
    # Authorization header would go to whatever host a redirect names. The
    # API never redirects; a redirect is answered as the error it is.
    def redirect_request(self, *args, **kwargs):
        return None


def _context() -> ssl.SSLContext:
    """Full verification, against XYMONAPI_CA when set, the system's store
    otherwise. Never less: the token rides on this connection."""
    ctx = ssl.create_default_context()
    if CA:
        try:
            ctx.load_verify_locations(CA)
        except (OSError, ssl.SSLError) as e:
            raise APIError(f"cannot use XYMONAPI_CA={CA}: {e}") from e
    return ctx


_opener: urllib.request.OpenerDirector | None = None


def open_url(req, timeout: float):
    """urlopen through the opener above: no redirect, full verification. The
    opener is built on the first call, not when the module is imported, so
    that a wrong XYMONAPI_CA is an APIError each tool and command reports,
    rather than a crash before the MCP server has answered anything."""
    global _opener
    if _opener is None:
        _opener = urllib.request.build_opener(
            _NoRedirect, urllib.request.HTTPSHandler(context=_context()))
    return _opener.open(req, timeout=timeout)


# The xymonapi version this client was written for, the floor in the PLUGIN
# file beside this one; tests/api/xymonapi-auth.sh checks the two agree.
# The API keeps its answers within a major version, so a newer one is fine.
API_FLOOR = "0.1.0"
_TRIPLE = re.compile(r"(\d+)\.(\d+)\.(\d+)")
_warning: str | None = None


def _triple(version: str) -> tuple[int, int, int] | None:
    m = _TRIPLE.search(version)
    return (int(m[1]), int(m[2]), int(m[3])) if m else None


def version_warning() -> str:
    """What to do when the API is older than this client was written for,
    asked of /health once per process; "" when it is not, or does not say
    its version (a server from before it did), or does not answer. Nothing
    is updated from here: the server's admin does that."""
    global _warning
    if _warning is None:
        _warning = ""
        try:
            theirs = api("/health").get("version", "")
        except APIError:
            return _warning
        t = _triple(theirs)
        if t and t < _triple(API_FLOOR):
            _warning = (f"the API at {URL} is xymonapi {theirs}; this client needs {API_FLOOR} or later: "
                        "make install on the server, from a newer checkout of xymon-plugins, brings it up to date")
            # Once, on stderr, which an MCP client logs: stdout is the protocol.
            print(f"xymonapi: {_warning}", file=sys.stderr)
    return _warning


# An answer of the API is a board or a list of events: never near this.
MAX_BODY = 16 * 1024 * 1024


def api(path: str, **params: str | None) -> dict:
    """GET PATH under /xymon/api/v1 and return the JSON it answers."""
    # http and https only: urllib also reads file:// and ftp:// URLs.
    if urlsplit(URL).scheme not in ("http", "https"):
        raise APIError(f"XYMONAPI_URL must be an http:// or https:// URL, not {URL!r}")
    # Left out when not given; "0" is a value.
    query = urlencode({k: v for k, v in params.items() if v is not None and v != ""})
    # This call's identifier, which the API logs and sends back: an error
    # says it, so that the API's log line about it can be found.
    rid = secrets.token_hex(8)
    try:
        req = urllib.request.Request(f"{URL}/xymon/api/v1{path}" + (f"?{query}" if query else ""),
                                     headers={"X-Request-Id": rid})
        bearer = _token()
        if bearer:
            req.add_header("Authorization", f"Bearer {bearer}")
        with open_url(req, 30) as r:
            body = r.read(MAX_BODY + 1)
        if len(body) > MAX_BODY:
            raise APIError(f"xymonapi at {URL} answered more than {MAX_BODY} bytes")
        return json.loads(body)
    except urllib.error.HTTPError as e:
        # The API's own explanation, not a bare status; and for the two
        # failures of a first setup, what to check.
        detail = e.read().decode(errors="replace")
        if e.code == 401:
            detail += (" -- the token in XYMONAPI_TOKEN_FILE was revoked or replaced: run the "
                       "setup script from /client again" if (TOKEN or TOKEN_FILE) else
                       " -- set XYMONAPI_TOKEN_FILE: the setup script from /client gets this "
                       "machine a token and writes it")
        rid = e.headers.get("X-Request-Id", rid) if e.headers else rid
        raise APIError(f"xymonapi answered {e.code}: {detail} (request id {rid})", e.code) from e
    except urllib.error.URLError as e:
        if isinstance(e.reason, ssl.SSLCertVerificationError):
            raise APIError(f"xymonapi at {URL} has a certificate this machine does not trust: "
                           f"{e.reason.verify_message} -- name the server's certificate, or the "
                           "CA that signed it, in XYMONAPI_CA") from e
        raise APIError(f"cannot reach xymonapi at {URL}: {e.reason} -- is the API running, and "
                       "XYMONAPI_URL right? From another machine it is reached over HTTPS, "
                       "as xymonapi(8) says") from e
    except ValueError as e:              # a URL urllib cannot use, or an answer that is not JSON
        raise APIError(f"xymonapi at {URL}: {e}") from e
    except OSError as e:                 # the connection broke, or timed out, while reading
        raise APIError(f"xymonapi at {URL}: {e}") from e

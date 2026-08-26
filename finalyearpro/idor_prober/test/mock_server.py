#!/usr/bin/env python3
"""
Enhanced mock vulnerable API for testing idor_prober.

Endpoints:
1. GET/POST/PUT/DELETE /user/{id}/profile - Vulnerable profile lookup (no auth check)
2. GET/POST/PUT/DELETE /safe/{id}/profile - Safe profile lookup (checks token ownership)
3. GET/POST/PUT/DELETE /api/v1/users/{id}/orders - Vulnerable orders lookup (no auth check)
4. GET/POST/PUT/DELETE /api/v1/users/{id}/settings - Vulnerable GET/POST/PUT/DELETE settings endpoint
5. GET/POST/PUT/DELETE /api/v1/admin/users/{id} - Safe admin endpoint (returns 403 for non-admin tokens)
6. GET/POST/PUT/DELETE /api/v1/documents/{id} - Vulnerable document lookup (same structure, different values per user)
7. GET/POST/PUT/DELETE /api/v1/shared/config - Ambiguous/shared data (identical for all users)
8. GET/POST/PUT/DELETE /api/v1/users/{id}/avatar - Non-JSON binary PNG response
9. GET/POST/PUT/DELETE /api/v1/users/{id}/timeline - Timing side-channel endpoint (500ms delay for cross-account access)
"""
from http.server import BaseHTTPRequestHandler, HTTPServer
import json
import re
import time

USERS = {
    "1001": {"id": 1001, "name": "Alice", "email": "alice@corp.com", "balance": 4200.50},
    "2002": {"id": 2002, "name": "Bob", "email": "bob@corp.com", "balance": 10.00},
    "3003": {"id": 3003, "name": "Charlie", "email": "charlie@corp.com", "balance": 750.00},
}

TOKEN_OWNERS = {
    "1001": "userA-token",
    "2002": "userB-token",
    "3003": "userC-token",
}

ADMIN_TOKENS = {
    "admin-token",
    "userAdmin-token",
    "admin",
    "secret-admin-token",
}

ORDERS = {
    "1001": [
        {"order_id": "ord-1001-1", "item": "Laptop", "price": 1200.00, "status": "shipped"},
        {"order_id": "ord-1001-2", "item": "Mouse", "price": 25.00, "status": "delivered"},
    ],
    "2002": [
        {"order_id": "ord-2002-1", "item": "Headphones", "price": 150.00, "status": "delivered"},
    ],
    "3003": [
        {"order_id": "ord-3003-1", "item": "Keyboard", "price": 80.00, "status": "processing"},
    ],
}

SETTINGS = {
    "1001": {"theme": "dark", "notifications": True, "email_alerts": True, "privacy": "private"},
    "2002": {"theme": "light", "notifications": False, "email_alerts": True, "privacy": "public"},
    "3003": {"theme": "system", "notifications": True, "email_alerts": False, "privacy": "friends"},
}

DOCUMENTS = {
    "1001": {
        "doc_id": 1001,
        "owner_id": 1001,
        "title": "Alice Financial Report 2026",
        "content": "Confidential financial statement for Alice",
        "classification": "restricted",
        "created_at": "2026-01-15T09:00:00Z",
    },
    "2002": {
        "doc_id": 2002,
        "owner_id": 2002,
        "title": "Bob Medical Report 2026",
        "content": "Private health evaluation report for Bob",
        "classification": "confidential",
        "created_at": "2026-02-20T14:30:00Z",
    },
    "3003": {
        "doc_id": 3003,
        "owner_id": 3003,
        "title": "Charlie Employment Contract",
        "content": "Non-disclosure and service terms for Charlie",
        "classification": "internal",
        "created_at": "2026-03-10T11:15:00Z",
    },
}

DOC_ALIAS = {
    "1": "1001",
    "2": "2002",
    "3": "3003",
}

SHARED_CONFIG = {
    "app_name": "IDOR Prober Test Platform",
    "version": "1.0.0",
    "environment": "testing",
    "maintenance": False,
    "features": ["auth", "users", "orders", "settings"],
}

TIMELINE = {
    "1001": {
        "user_id": 1001,
        "events": [
            {"event": "login", "timestamp": "2026-07-01T10:00:00Z"},
            {"event": "password_change", "timestamp": "2026-07-05T14:20:00Z"},
        ],
    },
    "2002": {
        "user_id": 2002,
        "events": [
            {"event": "login", "timestamp": "2026-07-02T11:00:00Z"},
            {"event": "profile_update", "timestamp": "2026-07-06T15:10:00Z"},
        ],
    },
    "3003": {
        "user_id": 3003,
        "events": [
            {"event": "login", "timestamp": "2026-07-03T12:00:00Z"},
            {"event": "settings_update", "timestamp": "2026-07-07T16:00:00Z"},
        ],
    },
}

AVATAR_BYTES = bytes([
    0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A,
    0x00, 0x00, 0x00, 0x0D, 0x49, 0x48, 0x44, 0x52,
    0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01,
    0x08, 0x06, 0x00, 0x00, 0x00, 0x1F, 0x15, 0xC4,
    0x89, 0x00, 0x00, 0x00, 0x0A, 0x49, 0x44, 0x41,
    0x54, 0x78, 0x9C, 0x63, 0x00, 0x01, 0x00, 0x00,
    0x05, 0x00, 0x01, 0x0D, 0x0A, 0x2D, 0xB4, 0x00,
    0x00, 0x00, 0x00, 0x49, 0x45, 0x4E, 0x44, 0xAE,
    0x42, 0x60, 0x82
])


class Handler(BaseHTTPRequestHandler):
    def _get_session(self):
        cookie = self.headers.get("Cookie", "")
        m = re.search(r"session=([\w-]+)", cookie)
        if m:
            return m.group(1)
        auth = self.headers.get("Authorization", "")
        if auth:
            m = re.search(r"(?:Bearer\s+)?([\w-]+)", auth)
            if m:
                return m.group(1)
        for hdr in ["X-Session-Token", "X-Token", "X-Api-Key"]:
            val = self.headers.get(hdr, "")
            if val:
                return val.strip()
        return None

    def _cookie_session(self):
        return self._get_session()

    def _send_json(self, code, obj):
        body = json.dumps(obj).encode()
        self.send_response(code)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def _send_bytes(self, code, content_type, body_bytes):
        self.send_response(code)
        self.send_header("Content-Type", content_type)
        self.send_header("Content-Length", str(len(body_bytes)))
        self.end_headers()
        self.wfile.write(body_bytes)

    def _read_json_body(self):
        try:
            content_length = int(self.headers.get("Content-Length", 0))
            if content_length > 0:
                raw_body = self.rfile.read(content_length).decode("utf-8")
                return json.loads(raw_body)
        except Exception:
            pass
        return {}

    def _dispatch(self, method):
        session = self._get_session()

        # 1. /user/{id}/profile - Vulnerable endpoint
        m = re.match(r"^/user/([^/]+)/profile$", self.path)
        if m:
            uid = m.group(1)
            if uid not in USERS:
                return self._send_json(404, {"error": "not found"})
            return self._send_json(200, USERS[uid])

        # 2. /safe/{id}/profile - Safe endpoint
        m = re.match(r"^/safe/([^/]+)/profile$", self.path)
        if m:
            uid = m.group(1)
            owner = TOKEN_OWNERS.get(uid)
            if not owner or session != owner:
                return self._send_json(403, {"error": "access denied"})
            if uid not in USERS:
                return self._send_json(404, {"error": "not found"})
            return self._send_json(200, USERS[uid])

        # 3. /api/v1/users/{id}/orders - Vulnerable orders endpoint
        m = re.match(r"^/api/v1/users/([^/]+)/orders$", self.path)
        if m:
            uid = m.group(1)
            if uid not in USERS:
                return self._send_json(404, {"error": "not found"})
            return self._send_json(200, {"user_id": int(uid) if uid.isdigit() else uid, "orders": ORDERS.get(uid, [])})

        # 4. /api/v1/users/{id}/settings - Vulnerable GET/POST/PUT/DELETE settings endpoint
        m = re.match(r"^/api/v1/users/([^/]+)/settings$", self.path)
        if m:
            uid = m.group(1)
            if uid not in USERS:
                return self._send_json(404, {"error": "not found"})

            if method in ("POST", "PUT"):
                body = self._read_json_body()
                if uid not in SETTINGS:
                    SETTINGS[uid] = {}
                if isinstance(body, dict):
                    SETTINGS[uid].update(body)
                return self._send_json(200, {
                    "status": "success",
                    "message": f"Settings updated for user {uid}",
                    "settings": SETTINGS[uid]
                })
            elif method == "DELETE":
                SETTINGS[uid] = {}
                return self._send_json(200, {
                    "status": "success",
                    "message": f"Settings cleared for user {uid}"
                })
            else:
                return self._send_json(200, SETTINGS.get(uid, {}))

        # 5. /api/v1/admin/users/{id} - Safe admin endpoint
        m = re.match(r"^/api/v1/admin/users/([^/]+)$", self.path)
        if m:
            uid = m.group(1)
            if session not in ADMIN_TOKENS:
                return self._send_json(403, {"error": "access denied", "message": "Admin privileges required"})
            if uid not in USERS:
                return self._send_json(404, {"error": "not found"})
            return self._send_json(200, USERS[uid])

        # 6. /api/v1/documents/{id} - Shape vs value similarity test endpoint
        m = re.match(r"^/api/v1/documents/([^/]+)$", self.path)
        if m:
            did = m.group(1)
            mapped_id = DOC_ALIAS.get(did, did)
            if mapped_id not in DOCUMENTS:
                return self._send_json(404, {"error": "document not found"})
            return self._send_json(200, DOCUMENTS[mapped_id])

        # 7. /api/v1/shared/config - Ambiguous/shared data endpoint
        if re.match(r"^/api/v1/shared/config$", self.path):
            return self._send_json(200, SHARED_CONFIG)

        # 8. /api/v1/users/{id}/avatar - Non-JSON binary response endpoint
        m = re.match(r"^/api/v1/users/([^/]+)/avatar$", self.path)
        if m:
            uid = m.group(1)
            if uid not in USERS:
                return self._send_json(404, {"error": "not found"})
            return self._send_bytes(200, "image/png", AVATAR_BYTES)

        # 9. /api/v1/users/{id}/timeline - Timing-based side-channel endpoint
        m = re.match(r"^/api/v1/users/([^/]+)/timeline$", self.path)
        if m:
            uid = m.group(1)
            owner = TOKEN_OWNERS.get(uid)
            if session != owner:
                time.sleep(0.5)
            if uid not in USERS:
                return self._send_json(404, {"error": "not found"})
            return self._send_json(200, TIMELINE.get(uid, {}))

        self._send_json(404, {"error": "not found"})

    def do_GET(self):
        self._dispatch("GET")

    def do_POST(self):
        self._dispatch("POST")

    def do_PUT(self):
        self._dispatch("PUT")

    def do_DELETE(self):
        self._dispatch("DELETE")

    def log_message(self, fmt, *args):
        pass  # quiet


if __name__ == "__main__":
    server = HTTPServer(("127.0.0.1", 8899), Handler)
    print("Mock server on http://127.0.0.1:8899")
    server.serve_forever()

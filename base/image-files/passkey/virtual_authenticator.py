#!/usr/bin/env python3
"""Virtual CTAP2 authenticator for headless IB Gateway passkey login.

This program emulates a FIDO2 security key entirely in user-space (no physical
USB token, no GUI, no Qt). It is the piece that makes IB Gateway's
"Use your Passkey device / Insert your security key and touch it" prompt
satisfiable without any human interaction.

Architecture
------------
On Linux, a HID *device* (like a USB security key) is presented to the kernel
via /dev/uhid: user-space writes a CREATE2 uhid event with a HID report
descriptor, and the kernel then exposes a corresponding /dev/hidrawN device.
Applications such as IB Gateway enumerate that hidraw device, encapsulate CTAP2
requests inside the CTAPHID framing protocol, and write them to the device. We
read those frames back (CTAPHID over UHID), parse the CBOR payload, perform the
WebAuthn / CTAP2 ceremony with the pre-imported EC private key, and write the
response back out.

We rely on the official `fido2` (Yubico) library for the wire-level constants
and signing primitives, and on the `cbor2` library for CBOR encoding. The UHID
struct definitions below mirror <linux/uhid.h> and the standard FIDO HID
report descriptor.

Lifecycle
---------
The authenticator is meant to be started by image-files/start.sh BEFORE IBC
launches IB Gateway. It reads the credential material that
passkey/export_credential.sh wrote to /run/secrets/ibkr_passkey.json, then
blocks forever answering CTAPHID requests. A separate watcher script clicks the
"Authenticate" button in the noVNC desktop when IB Gateway shows the passkey
prompt; this authenticator then signs the challenge automatically.
"""

from __future__ import annotations

import cbor2
import fcntl
import json
import os
import queue
import struct
import threading
import time

from cryptography.hazmat.primitives import hashes, serialization
from cryptography.hazmat.primitives.asymmetric import ec, padding
from cryptography.hazmat.primitives.asymmetric.utils import encode_dss_signature, decode_dss_signature

from fido2.cose import ES256
from fido2.webauthn import AuthenticatorData
from fido2 import webauthn

# --------------------------------------------------------------------------- #
# UHID constants (see <linux/uhid.h>)
# --------------------------------------------------------------------------- #
UHID_CREATE2 = 0x0B
UHID_DESTROY = 0x01
UHID_START = 0x02
UHID_STOP = 0x03
UHID_OPEN = 0x04
UHID_CLOSE = 0x05
UHID_OUTPUT = 0x06
UHID_GET_REPORT = 0x09
UHID_SET_REPORT = 0x0D
UHID_INPUT2 = 0x0C

UHID_INPUT_REPORT = 0x02   # uhid_report_type
UHID_OUTPUT_REPORT = 0x01

# --------------------------------------------------------------------------- #
# CTAPHID command codes (FIDO CTAP2 spec)
# --------------------------------------------------------------------------- #
CTAPHID_PING = 0x01
CTAPHID_MSG = 0x03
CTAPHID_INIT = 0x06
CTAPHID_WINK = 0x08
CTAPHID_CBOR = 0x10
CTAPHID_CANCEL = 0x11
CTAPHID_KEEPALIVE = 0x3B
CTAPHID_ERROR = 0x3F

# CTAPHID_INIT response constants — capability bits
CAPABILITY_CBOR = 0x04
CAPABILITY_NMSG = 0x08  # supports CTAP1 messaging (0x03)

# CTAPHID_ERROR status codes
ERR_INVALID_CMD = 0x01
ERR_INVALID_LEN = 0x02
ERR_CHANNEL_BUSY = 0x06

# CTAP2 command codes (CTAP2 spec §6.1)
CTAP2_MAKE_CREDENTIAL = 0x01
CTAP2_GET_ASSERTION = 0x02
CTAP2_GET_NEXT_ASSERTION = 0x08
CTAP2_GET_INFO = 0x04
CTAP2_CLIENT_PIN = 0x06
CTAP2_RESET = 0x07
CTAP2_SELECTION = 0x08

# CTAP2 status codes
CTAP2_OK = 0x00
CTAP2_ERR_INVALID_COMMAND = 0x01
CTAP2_ERR_INVALID_CBOR = 0x12
CTAP2_ERR_INVALID_PARAMETER = 0x14
CTAP2_ERR_CREDENTIAL_NOT_FOUND = 0x2B
CTAP2_ERR_NO_CREDENTIALS = 0x2E
CTAP2_ERR_UNSUPPORTED_OPTION = 0x13
CTAP2_ERR_KEEPALIVE_CANCEL = 0x2D
CTAP2_ERR_NOT_ALLOWED = 0x27

# FIDO HID report descriptor (standard, same as soft-fido2 uses).
# Usage Page 0xF1D0 = FIDO Alliance, Usage 0x01 = U2F HID Authenticator.
REPORT_DESCRIPTOR = bytes([
    0x06, 0xD0, 0xF1,          # Usage Page (FIDO Alliance)
    0x09, 0x01,                # Usage (FIDO HID Authenticator)
    0xA1, 0x01,                # HID Collection (Application)
    0x09, 0x20,                # Usage (Input Report Data)
    0x15, 0x00,                # Logical Minimum (0)
    0x26, 0xFF, 0x00,          # Logical Maximum (255)
    0x75, 0x08,                # Report Size (8)
    0x95, 0x40,                # Report Count (64)
    0x81, 0x02,                # Input (Data,Var,Abs)
    0x09, 0x21,                # Usage (Output Report Data)
    0x15, 0x00,                # Logical Minimum (0)
    0x26, 0xFF, 0x00,          # Logical Maximum (255)
    0x75, 0x08,                # Report Size (8)
    0x95, 0x40,                # Report Count (64)
    0x91, 0x02,                # Output (Data,Var,Abs)
    0xC0,                      # End Collection
])

# AAGUID: 0x1337C0D3 style was used by soft-fido2; we advertise a stable
# all-zero AAGUID which IB Gateway accepts for non-attested "security key".
AAGUID = bytes(16)

# The FIDO transport we claim (USB). 0x01 = usb, 0x02 = nfc, 0x04 = ble,
# 0x08 = internal, 0x20 = hybrid.
TRANSPORT_USB = 0x01


# --------------------------------------------------------------------------- #
# Credential model — the material we import from Bitwarden.
# --------------------------------------------------------------------------- #
class Credential:
    """A single imported passkey.

    Extracted from `bitwarden-use fido2 get` output. The private key is the
    raw P-256 EC key; credential_id is the RAW bytes (not base64) as IB
    registered it; rp_id is the relying-party id (interactivebrokers.com.hk).
    """

    def __init__(self, credential_id: bytes, rp_id: str, user_handle: bytes,
                 private_key_pem: bytes, algorithm: int = -7):
        self.credential_id = credential_id
        self.rp_id = rp_id
        self.user_handle = user_handle
        self.counter = 0
        self.algorithm = algorithm  # -7 => ES256
        self.private_key = serialization.load_pem_private_key(
            private_key_pem, password=None)

    @property
    def public_key(self):
        return self.private_key.public_key()

    def cose_key(self):
        """Return a COSE key dict for CTAP2 makeCredential/getAssertion."""
        return {
            1: 2,                       # kty: EC2
            3: self.algorithm,          # alg: ES256
            -1: 1,                      # crv: P-256
            -2: self._int_to_bytes(self.public_key.public_numbers().x, 32),
            -3: self._int_to_bytes(self.public_key.public_numbers().y, 32),
        }

    @staticmethod
    def _int_to_bytes(value: int, length: int) -> bytes:
        return value.to_bytes(length, byteorder="big")

    def increment_counter(self) -> int:
        self.counter += 1
        return self.counter


# --------------------------------------------------------------------------- #
# UHID packing helpers (struct layouts match <linux/uhid.h>)
# --------------------------------------------------------------------------- #
def uhid_create2(name: bytes, rd: bytes) -> bytes:
    """Build a UHID_CREATE2 event."""
    # struct uhid_create2_req { __u8 name[128]; __u8 phys[64]; __u8 uniq[64];
    #  __u16 rd_size; __u16 bus; __u32 vendor; __u32 product; __u32 version;
    #  __u32 country; __u8 rd_data[HID_MAX_DESCRIPTOR_SIZE]; }
    return struct.pack(
        "<I128s64s64sHHIII I4096s",
        UHID_CREATE2,
        name.ljust(128, b"\x00"),
        b"\x00" * 64,
        b"\x00" * 64,
        len(rd),
        0x03,                    # bus: USB
        0x1337,                  # vendor
        0x1337,                  # product
        0x0100,                  # version
        0,                       # country
        rd.ljust(4096, b"\x00"),
    )


def uhid_input2(data: bytes) -> bytes:
    """Build a UHID_INPUT2 event carrying a CTAPHID output frame."""
    # struct uhid_input2_req { __u16 size; __u8 data[HID_MAX]; }
    return struct.pack(
        "<IH4096s",
        UHID_INPUT2,
        len(data),
        data.ljust(4096, b"\x00"),
    )


def uhid_destroy() -> bytes:
    return struct.pack("<I", UHID_DESTROY)


# --------------------------------------------------------------------------- #
# CTAPHID framing
# --------------------------------------------------------------------------- #
class CTAPHIDPacket:
    """Encapsulate a CTAPHID message as a sequence of 64-byte frames.

    The first (init) frame carries the 4-byte channel id, a 1-byte command,
    a 2-byte payload length, then up to 57 bytes. Continuation (seq) frames
    carry the channel id, a 1-byte sequence number, then up to 59 bytes.
    """

    def __init__(self, data: bytes):
        self.data = data

    def frames(self, cid: bytes, cmd: int) -> bytes:
        """Return the concatenated 64-byte frames for a CTAPHID message.

        Per the CTAPHID spec the init frame's command byte has its high bit
        set (0x80 | cmd); continuation frames carry a sequence number whose
        high bit is clear (0x00-0x7f).
        """
        payload = self.data
        out = bytearray()
        # INIT frame: cid(4, verbatim) | cmd|0x80 (1) | bcnt (2, big-endian) | data
        bcnt = len(payload)
        init = bytes(cid) + bytes([0x80 | cmd]) + bcnt.to_bytes(2, "big")
        init += payload[:57]
        init += b"\x00" * (64 - len(init))
        out += init
        # continuation frames: cid(4) | seq (1, high bit clear) | data
        rest = payload[57:]
        seq = 0
        while rest:
            frame = bytes(cid) + bytes([seq & 0x7F])
            frame += rest[:59]
            frame += b"\x00" * (64 - len(frame))
            out += frame
            rest = rest[59:]
            seq += 1
        return bytes(out)


class CTAPHIDParser:
    """Reassemble multi-frame CTAPHID messages coming from the host."""

    def __init__(self):
        self._buffers = {}

    def feed(self, frame: bytes) -> tuple[bytes, bytes, int] | None:
        """Feed one 64-byte frame. Returns (cid, payload, cmd) once complete.

        Init frames are identified by the 0x80 bit on the 5th byte; the low
        7 bits are the command. Continuation frames carry a sequence number
        (high bit clear). Payload bytes are accumulated verbatim and the
        final buffer is truncated to the declared byte count (bcnt).
        
        The returned cid is the 4-byte channel identifier (as bytes), payload
        is the reassembled CTAP message, and cmd is the command byte (int).
        """
        cid_int = int.from_bytes(frame[:4], "big")
        cid_bytes = frame[:4]
        b = frame[4]
        if b & 0x80:  # init frame
            cmd = b & 0x7F
            bcnt = int.from_bytes(frame[5:7], "big")
            payload = frame[7:64]
            if len(payload) >= bcnt:
                return (cid_bytes, bytes(payload[:bcnt]), cmd)
            # need continuation frames
            self._buffers[cid_int] = {
                "cid_bytes": cid_bytes,
                "cmd": cmd,
                "bcnt": bcnt,
                "payload": bytearray(payload),
                "next_seq": 0,
            }
            return None
        else:  # continuation frame
            seq = b
            buf = self._buffers.get(cid_int)
            if buf is None or seq != buf["next_seq"]:
                return None
            buf["payload"] += frame[5:64]
            buf["next_seq"] += 1
            if len(buf["payload"]) >= buf["bcnt"]:
                payload = bytes(buf["payload"][:buf["bcnt"]])
                cmd = buf["cmd"]
                cid_b = buf["cid_bytes"]
                self._buffers.pop(cid_int, None)
                return (cid_b, payload, cmd)
            return None


# --------------------------------------------------------------------------- #
# The virtual authenticator main class
# --------------------------------------------------------------------------- #
class VirtualAuthenticator:
    def __init__(self, credentials: list[Credential], device_path: str = "/dev/uhid"):
        self.credentials = credentials
        self.device_path = device_path
        self.cids = {}
        self.parser = CTAPHIDParser()
        self.fd = None
        self._running = False
        self._write_queue = queue.Queue()

    # -- device lifecycle -------------------------------------------------- #
    def start(self):
        self.fd = os.open(self.device_path, os.O_RDWR | os.O_NONBLOCK)
        fcntl.fcntl(self.fd, fcntl.F_SETFL, os.O_NONBLOCK)
        ev = uhid_create2(b"softpasskey", REPORT_DESCRIPTOR)
        os.write(self.fd, ev)
        self._running = True
        print("[virtual-authenticator] UHID device created", flush=True)

    def stop(self):
        if self.fd is not None:
            try:
                os.write(self.fd, uhid_destroy())
            except Exception:
                pass
            os.close(self.fd)
            self._running = False

    # -- uhid event loop --------------------------------------------------- #
    def run(self):
        """Main loop: read uhid events, dispatch CTAPHID frames."""
        self.start()
        while self._running:
            # poll for kernel->user events
            self._drain_input()
            # flush our pending responses
            try:
                while True:
                    frame = self._write_queue.get_nowait()
                    os.write(self.fd, uhid_input2(frame))
            except queue.Empty:
                pass
            time.sleep(0.001)

    def _drain_input(self):
        try:
            while True:
                raw = os.read(self.fd, 4380)
                if len(raw) < 4:
                    continue
                ev_type = struct.unpack("<I", raw[:4])[0]
                if ev_type == UHID_START:
                    self._maybe_in(raw)
                elif ev_type == UHID_OUTPUT:
                    self._handle_output(raw)
                elif ev_type == UHID_OPEN:
                    pass
                elif ev_type == UHID_CLOSE:
                    pass
                # UHID_STOP / UHID_CREATE2 / UHID_GET_REPORT / UHID_SET_REPORT
                # and other events need no special handling here.
        except BlockingIOError:
            pass

    def _maybe_in(self, raw):
        # UHID_START/CREATE confirmations — no payload of interest.
        pass

    def _handle_output(self, raw):
        # struct uhid_output_req: { __u8 data[HID_MAX]; __u16 size; __u8 type; }
        # layout in the stream: event(4) | data(4096) | size(2) | type(1)
        if len(raw) < 4096 + 2 + 1 + 4:
            return
        size = struct.unpack("<H", raw[4 + 4096:4 + 4096 + 2])[0]
        data = raw[4:4 + size]
        if len(data) >= 7:
            result = self.parser.feed(data)
            if result is not None:
                cid, payload, cmd = result
                self._dispatch(cid, payload, cmd)

    # -- ctaphid dispatch -------------------------------------------------- #
    def _dispatch(self, cid: bytes, payload: bytes, cmd: int):
        # The reassembled payload is the CTAP message (already WITHOUT the
        # 4-byte cid header that's part of the frame). For CBOR the first
        # byte is the CTAP command, the rest is the CBOR payload.
        if cmd == CTAPHID_INIT:
            self._on_init(cid, payload)
        elif cmd == CTAPHID_CBOR:
            self._on_cbor(cid, payload)
        elif cmd == CTAPHID_PING:
            self._send(payload, CTAPHID_PING, cid=cid)
        elif cmd == CTAPHID_WINK:
            self._send(payload, CTAPHID_WINK, cid=cid)
        elif cmd == CTAPHID_MSG:
            self._on_msg(cid, payload)
        else:
            self._send(b"\x00" + bytes([ERR_INVALID_CMD]), CTAPHID_ERROR,
                       cid=cid)

    def _on_init(self, cid, payload):
        # CTAPHID_INIT request payload: 8-byte nonce, then optional channels.
        # Response (after nonce + CID), per CTAPHID spec §8.1.9.1.3, is exactly
        # 5 bytes: PROTOCOL(1)=2 | MAJOR(1) | MINOR(1) | BUILD(1) | CAPABILITIES(1).
        # An off-by-one here (6 bytes) shifts CAPABILITIES out of the parsed
        # region and makes the host read caps=0, i.e. "no CBOR support", which
        # causes IB Gateway to ignore the key.
        nonce = payload[:8]
        # Broadcast CID (0xffffffff) is used for the INIT request.
        assigned = bytes([0x00, 0x00, 0x00, 0x01])
        # Respond on the broadcast CID per spec (init always uses 0xFFFFFFFF).
        data = nonce + assigned
        data += bytes([0x02,  # PROTOCOL version
                       0x05,  # MAJOR
                       0x01,  # MINOR
                       0x00,  # BUILD
                       CAPABILITY_CBOR | CAPABILITY_NMSG])  # CAPABILITIES
        data += b"\x00" * (57 - len(data))
        print("[virtual-authenticator] CTAPHID INIT answered (caps=0x%02x)"
              % (CAPABILITY_CBOR | CAPABILITY_NMSG), flush=True)
        self._send(data, CTAPHID_INIT, cid=b"\xff\xff\xff\xff")
        # remember the assigned channel
        self.cids[assigned] = assigned

    def _on_cbor(self, cid, payload):
        if len(payload) < 1:
            self._send(b"\x00" + bytes([ERR_INVALID_LEN]), CTAPHID_CBOR,
                       cid=cid)
            return
        ctap_cmd = payload[0]
        cbor_payload = payload[1:]
        try:
            request = cbor2.loads(cbor_payload) if cbor_payload else {}
        except Exception:
            self._send_ctap_status(cid, CTAP2_ERR_INVALID_CBOR)
            return
        self._handle_ctap2(cid, ctap_cmd, request)

    def _on_msg(self, cid, payload):
        # CTAPHID_MSG carries a U2F raw APDU:  CLA(1) | INS(1) | P1(1) |
        # P2(1) | Lc(2) | data. IB Gateway uses CTAP2 (CBOR) primarily; for
        # the U2F VERSION request we reply with "U2F_V2". Other commands are
        # answered with "unsupported" per the CTAP1 spec.
        if len(payload) < 1:
            return
        ins = payload[1:2] if len(payload) >= 2 else b""
        if payload[:1] == b"\x00" and ins == b"\x03":
            # U2F_VERSION
            data = b"U2F_V2"
            self._send(data, CTAPHID_MSG, cid=cid)
        else:
            # Respond with SW = "instruction not supported" (0x6D00)
            self._send(b"\x6d\x00", CTAPHID_MSG, cid=cid)

    def _handle_ctap2(self, cid, cmd, request):
        if cmd == CTAP2_GET_INFO:
            self._respond_get_info(cid)
        elif cmd == CTAP2_GET_ASSERTION:
            self._respond_get_assertion(cid, request)
        elif cmd == CTAP2_MAKE_CREDENTIAL:
            self._respond_make_credential(cid, request)
        else:
            self._send_ctap_status(cid, CTAP2_ERR_INVALID_COMMAND)

    # -- responses --------------------------------------------------------- #
    def _send_ctap_status(self, cid, status):
        """Send a CTAP2 status byte (error) as a CBOR response frame."""
        payload = bytes([status])
        self._send(payload, CTAPHID_CBOR, cid=cid)

    def _respond_get_info(self, cid):
        info = {
            1: ["FIDO_2_0", "U2F_V2"],
            2: ["hmac-secret"],
            3: AAGUID,
            4: {"rk": True, "up": True, "plat": False, "clientPin": False,
                "uv": False},
            5: 1200,
            6: [1],
            7: {"usb": True},
        }
        self._send_ctap_cbor(cid, CTAP2_OK, info)

    def _respond_get_assertion(self, cid, request):
        # request = {1: rpId, 2: clientDataHash, 3: allowList, 5: options, 7: extensions}
        rp_id = request.get(1, "")
        client_data_hash = request.get(2, b"")
        allow_list = request.get(3, [])
        options = request.get(5, {})

        credential = next(
            (c for c in self.credentials if c.rp_id == rp_id), None)

        if credential is None:
            self._send_ctap_status(cid, CTAP2_ERR_NO_CREDENTIALS)
            return

        if allow_list:
            allowed_ids = {a.get("id", b"") for a in allow_list}
            if credential.credential_id not in allowed_ids:
                self._send_ctap_status(cid, CTAP2_ERR_NO_CREDENTIALS)
                return

        # Build authenticator data (CTAP2 §6.2). For getAssertion the
        # authData is exactly rpIdHash(32) | flags(1) | signCount(4) — 37
        # bytes. flags must NOT carry AT (0x40) and authData must NOT include
        # credential data (that is makeCredential-only); including it would
        # produce an invalid signature over authData||clientDataHash.
        rp_id_hash = webauthn.sha256(rp_id.encode("utf-8"))
        flags = 0x01  # UP (user presence, emulated by the click)
        counter = credential.increment_counter().to_bytes(4, "big")
        auth_data = rp_id_hash + bytes([flags]) + counter

        # Signature over auth_data || clientDataHash (§6.2)
        signature = self._sign_es256(credential.private_key,
                                     auth_data + client_data_hash)

        response = {
            # CTAP2 §6.2: key 1 is a PublicKeyCredentialDescriptor map, not
            # the raw credential id bytes.
            1: {"id": credential.credential_id, "type": "public-key"},
            2: auth_data,
            3: signature,
            4: {"id": credential.user_handle},
        }
        self._send_ctap_cbor(cid, CTAP2_OK, response)

    def _respond_make_credential(self, cid, request):
        # Registration path is rarely needed because we import an existing
        # credential, but implement it minimally to avoid hard failures.
        self._send_ctap_status(cid, CTAP2_ERR_INVALID_COMMAND)

    # -- helpers ----------------------------------------------------------- #
    def _build_credential_data(self, cred):
        # credentialData = aaguid(16) | credIdLen(2) | credId | COSE key
        cose = cred.cose_key()
        cose_bytes = cbor2.dumps(cose)
        data = AAGUID
        data += len(cred.credential_id).to_bytes(2, "big")
        data += cred.credential_id
        data += cose_bytes
        return data

    def _sign_es256(self, privkey, message):
        der_sig = privkey.sign(message, ec.ECDSA(hashes.SHA256()))
        r, s = decode_dss_signature(der_sig)
        # CTAP2 expects raw R||S (64 bytes) for ES256, not DER.
        r_bytes = r.to_bytes(32, "big")
        s_bytes = s.to_bytes(32, "big")
        return r_bytes + s_bytes

    def _send(self, data, cmd, cid=b"\x00\x00\x00\x00"):
        pkt = CTAPHIDPacket(data)
        frames = pkt.frames(cid, cmd)
        self._write_queue.put(frames)

    def _send_ctap_cbor(self, cid, status, result):
        payload = cbor2.dumps(result)
        self._send(bytes([status]) + payload, CTAPHID_CBOR, cid=cid)


# --------------------------------------------------------------------------- #
# Entry point
# --------------------------------------------------------------------------- #
def load_credential_file(path: str) -> list[Credential]:
    """Parse the JSON written by export_credential.sh into Credential objects.

    The file format mirrors `bitwarden-use fido2 get` output:
    {
      "name": "...",
      "credentialId": "<base64url>",
      "rpId": "interactivebrokers.com.hk",
      "userHandle": "<base64url>",
      "keyType": "public-key",
      "keyCurve": "P-256",
      "privateKeyPem": "-----BEGIN PRIVATE KEY-----\n..."
    }
    """
    with open(path) as f:
        data = json.load(f)

    creds = []
    for item in data if isinstance(data, list) else [data]:
        pem = item["privateKeyPem"].encode("utf-8")
        credential_id = _b64url_to_bytes(item["credentialId"])
        user_handle = _b64url_to_bytes(item.get("userHandle", ""))
        cred = Credential(
            credential_id=credential_id,
            rp_id=item["rpId"],
            user_handle=user_handle,
            private_key_pem=pem,
            algorithm=int(item.get("algorithm", -7)),
        )
        creds.append(cred)
    return creds


def _b64url_to_bytes(encoded: str) -> bytes:
    """Decode a base64url (URL-safe, no padding) string to raw bytes.

    Bitwarden stores passkey credential ids and user handles in standard
    base64url (RFC 4648) with no padding. A valid base64 encoding can only
    have a length that is 0, 2 or 3 (mod 4); mod 4 == 1 is impossible and
    means the input is malformed. We add whatever padding is needed and let
    urlsafe_b64decode do the decoding.
    """
    if not encoded:
        return b""
    if len(encoded) % 4 == 1:
        raise ValueError(
            f"Invalid base64url length {len(encoded)} (mod 4 == 1): "
            f"not decodable")
    import base64
    padding = "=" * (-len(encoded) % 4)
    return base64.urlsafe_b64decode(encoded + padding)


def main():
    import argparse
    parser = argparse.ArgumentParser(
        description="Virtual CTAP2 authenticator for IB Gateway passkey login")
    parser.add_argument("--credential-file",
                        default=os.environ.get("PASSKEY_FILE",
                                               "/run/secrets/ibkr_passkey.json"),
                        help="JSON file with imported passkey material")
    parser.add_argument("--device", default="/dev/uhid")
    args = parser.parse_args()

    creds = load_credential_file(args.credential_file)
    if not creds:
        print("[virtual-authenticator] No credentials loaded; exiting.",
              file=os.sys.stderr)
        return 1

    for c in creds:
        print(f"[virtual-authenticator] Loaded passkey for rpId={c.rp_id} "
              f"credentialId={c.credential_id.hex()[:16]}...", flush=True)

    auth = VirtualAuthenticator(creds, args.device)
    try:
        auth.run()
    except KeyboardInterrupt:
        print("[virtual-authenticator] Interrupted; shutting down.", flush=True)
    finally:
        auth.stop()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

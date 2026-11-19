---
name: pg-wire-encoding
description: Use when validating or correcting PG message byte encoding against reference PG source (C++ sending simulators or receivers such as CNWQosGateway.cpp). Applies to field widths, ASCII versus binary encoding, fixed-width padding, unexpected PG log values, rejected packets, and pack functions in TlvHelper.py, CdsHelper.py, or TcpHelper.py.
---

# Validating PG Wire Encoding

## Fundamental Rule

**The word "numeric" in a specification does not define the wire format.**
It can mean a one-byte binary value, one-byte ASCII character, or four-byte
big-endian integer. Confirm the wire format against PG source; do not guess when
the source is unavailable.

In a previous NWDAF eNB implementation, seven of eight fields were incorrectly
encoded based on specification tables, while every TC still passed.

## 1. Identify the Receiver's Parsing Strategy

This determines the risk.

**(A) Fixed order without tag validation**: repeated `p++; length = *p; p++;`.

```c
p++; length = *p; p++;
stQosInfo.stENBQosInfo.cSupportType = *p;
p = p + length;
```

A single incorrect field width shifts every subsequent field. Both order and width must match.

**(B) Tag-based `switch`**

```c
switch (*p) {
    case TAG_NET_TYPE1: ...
    case TAG_CONTROL_UNIT: ...
}
```

Order is flexible; field widths must still match.

**(C) Fixed-count loop**

```c
for (i = 0; i < 6; i++) { /* CATEGORY + QOS_POLICY */ }
```

The count is hardcoded. Sending five pairs makes the sixth iteration consume the following fields.

## 2. Field Width Clues: Hungarian Notation

| Prefix | Type | Wire representation |
|---|---|---|
| `c...` | `char` | 1B (`= *p`) or `char[]` (`memcpy(..., length)`) |
| `n...` | `int` | **4B big-endian** (with `ntohl`) |

```c
stQosInfo.cSupportType   = *p;                          // 1B
memcpy(&tmp, p, sizeof(int)); n = ntohl(tmp);           // 4B big-endian
memcpy(stQosInfo.cQCI, p, length);                      // String
```

The integer read preceding `ntohl` consumes four bytes regardless of the TLV length.
Sending one byte causes subsequent tag and length bytes to become part of the value.

## 3. ASCII Versus Binary: Check the Sender

Both formats can occur in the same file.

```c
temp = 0x02;
TLVGeneration(0x3A, 1, (void*)&temp, body);      // Binary 0x02
TLVGeneration(0x41, 1, (void*)"2", body);        // ASCII '2' = 0x32; string literal
temp = 0x30;
TLVGeneration(0x0C, 1, (void*)&temp, body);      // 0x30 = ASCII '0'
```

`(void*)"2"` points to a string literal whose first byte is `0x32`; it is different from `&temp`.
Log format specifiers also provide clues: `%c` prints a character; `%d` prints a parsed integer.

## 4. Fixed Width and Padding

```c
char strQosPolicy[LEN_QOS_POLICY+1] = { 0x00, };
sprintf(strQosPolicy, "QoS400K_NoGBR");
TLVGeneration(0x10, LEN_QOS_POLICY, strQosPolicy, body);   // Fixed width, NUL padding
```

Reproduce this with `pack_string_fixed(tag, val, length, pad=b'\x00')`.
The default padding is a space; specify NUL padding explicitly where required.

**Do not send an oversized field when the actual macro value is unknown.**
Some receiver fields lack upper-bound checks:

```c
if (length > 0) memcpy(cQosPolicy[i], p, length);   // No bound check: possible overflow
if (length > LEN_CELL_ID) memcpy(..., LEN_CELL_ID); // Bounded copy
```

Without a bound check, exceeding the real buffer width can overflow PG memory.
Until the width is confirmed, use the actual string length rather than an assumed larger width.

## 5. Reproduce the Receiver in Python

Check that the number of consumed bytes equals the total packet length.

```python
import sys, struct; sys.path.insert(0, 'libraries')
import TlvHelper as T

def pg_parse(buf):
    """Mirror the receiver's C parser: fixed order without tag validation."""
    p = 0
    def rd():
        nonlocal p
        p += 1; ln = buf[p]; p += 1
        v = buf[p:p+ln]; p += ln
        return ln, v
    out = {}
    _, v = rd(); out['cQosHdr']      = v[0]                       # 1B
    _, v = rd(); out['cSupportType'] = chr(v[0])                  # 1B ASCII
    _, v = rd(); out['nArpQCIFlag']  = struct.unpack('>I', v[:4])[0]
    ...
    return out, p

buf = b''.join(T.build_enb_qos_ctrl(...))
got, used = pg_parse(buf)
print('Consumed', used, '/ total', len(buf), '->', 'Match' if used == len(buf) else 'SHIFTED')
```

Reproduce the sending simulator's bytes and compare byte for byte:

```python
def tlv(tag, length, val):
    return bytes([tag, length]) + val[:length].ljust(length, b'\x00')
sim  = b''.join([tlv(0x3A, 1, bytes([0x10])), tlv(0x41, 1, b"2"), ...])
ours = b''.join(T.build_enb_qos_ctrl(...))
assert sim == ours, (T.hex_dump(sim), T.hex_dump(ours))
```

## 6. Compare Real PG Logs

The transmitted hexdump is recorded in `log.html` as `[TX→PG] packet = ...`.
Compare it with PG's `Header Info` and `BodyInfo` dumps.

An absent log entry does not necessarily mean parsing failed. PG's `BodyInfo`
printing omits some sections, including NWDAF pcefQoSCtrl/eNB/DPI.

An all-zero header dump indicates EOF: PG received zero bytes and printed its
zero-initialized buffer. This indicates a closed connection rather than a malformed packet.

## 7. Confirm Value Ranges Against Source

The receiver may reject values listed in the specification:

```c
else { gLog->Write(LOG_CRITICAL, "Unknown NetType [0x%02x]", ...); return nfwError; }
```

NWDAF `NETWORK=0x00` (2G) is one example: PG discards the message despite the value
appearing in the specification. Keep such TCs disabled and document the reason.

## After Making a Correction

- Update the encoding table in `tests/<iface>/AGENTS.md`.
- Add a build-only regression TC; `--dryrun` does not validate encoding.
- Put unconfirmed values in a single constant and record a TODO with the supporting evidence.

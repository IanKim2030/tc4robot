# SBI_NOTI — PCF SBI Noti reception (CDS · RTS common)

During SA (5G) subscriber processing, PG sends SBI Noti (HTTP/2) to PCF. The tool listens to the PCF role as Listen
This is because it is a section that is not visible to either the message (SC) or PDB.
The server is [libraries/HttpNotiServer.py](../../libraries/HttpNotiServer.py), and CDS and RTS are
Use the same port, , and the same server, .

| Where to use | what are you waiting for | Details |
|---|---|---|
| CDS | `1X`/`1Y` followed by `PG.BSUBS` → PCF Cell List (`TC-CDS-003`) | [../../tests/cds/AGENTS.md](../../tests/cds/AGENTS.md#pcf-sbi-noti-received--what-are-you-waiting-for) |
| RTS | Subscriber Notification after L1/L2 blocking | [../../tests/rts/AGENTS.md](../../tests/rts/AGENTS.md) |

## variable

| variable | default | Description |
|---|---|---|
| `${SNOTI_PCF_NOTI}` | `${TRUE}` | If you turn it off, Listen itself does not work (the suite runs without `h2`). `--no-sbi` |
| `${SBI_NOTI_PORT}` | `16101` | Listen port — Must match PG setting. Default value of node variables `${CDS_NOTI_PORT}` / `${RTS_NOTI_PORT}` |
| `${SBI_NOTI_HOST}` | `0.0.0.0` | bind address. Default value of node variables `${CDS_NOTI_HOST}` / `${RTS_NOTI_HOST}` |
| `${TOOL_HOST}` | None (environment file required) | PG reaches  tool address. CDS session `RES_URI`/`UDR_NOTI_URI` becomes host |

Waiting time (`${CDS_NOTI_WAIT}` 30s / `${RTS_NOTI_WAIT}` 12s) and link sampling period are determined separately for each node.
Even if you overwrite it in the environment file with the old name (`CDS_NOTI_PORT`, etc.), it continues to be used.

★ PG must be set to send to this address. The tool is not attached, but PG is attached.
Since it is a direction, it will not come if you just open the port. `0.0.0.0` is a bind address and cannot be used in the session URI —
So there is a separate `${TOOL_HOST}`. The URI literal of `config/db_seed/<env>.sql` sets the Robot variable to
Since it cannot be used, if the `TOOL_HOST` port changes, it must be changed as well.

## Protocol — HTTP/2 plaintext (h2c), prior-knowledge only

The protocol is HTTP/2 plain text (h2c). 3GPP SBI standard `http.server` is used in the first freeface.
Blocked — Process the frame directly with the `h2` package (sans-IO stack). `pip install h2`.

> If `No keyword with name 'Noti.Noti Server Start' found` appears, `h2` is not installed.
> In the past, `HttpNotiServer.py` did `import h2` at the top, so if there was no package,
> The  library itself is not loaded, and  Robot reported it with that message — the real cause is not at all
> It wasn't revealed. Currently, it is a delayed import, so when you start the server, you will see `pip install h2` instructions.
> If it fails and `${SNOTI_PCF_NOTI}=False`, the suite runs without `h2`.
> If the test equipment is different from the development PC, it must be installed on that equipment.
The only supported method is prior-knowledge, so if PG is attached as HTTP/1.1 Upgrade, it cannot be received.
“Non-h2c prior-knowledge connection” is left in `noti_errors()` — If you don’t get the notification, look here.

Connection establishment (free face + server SETTINGS) is counted separately from request reception — only with PG attached.
This is because it is necessary to distinguish between cases where notifications are sent later.

## Link Watch — Separate Thread

Monitoring thread that runs independently of the accept loop
Every `${CDS_NOTI_MONITOR_INTERVAL}` (default 1s), a sample of “how many are currently attached” is displayed.
It is  because it is impossible to know that the PG was disconnected in the middle of suite just by looking at the cumulative connection history. — The history is
It remains as is and appears as “connected”. If you don't get a notification, go to `Verify PCF Noti Received`
The link status during the TC, , is attached to the failure message.

```
{'live': 0, 'connected': False, 'total_connects': 1,
 'connects_since': 0, 'disconnects_since': 1, 'samples_with_no_link': 3, ...}
```

`disconnects_since` If is not 0, it is not a message but a broken link.

If you turn on `${CDS_NOTI_REQUIRE_LINK}` (default `${FALSE}`), links will be displayed before waiting for a notification.
First, check to see if he or she is alive. The reason the default is off may be the implementation where PG is added to each notification.
It is  — then the normal connection count is 0, so turning it on blocks the normal flow.

(RTS uses `${RTS_NOTI_MONITOR_INTERVAL}`, which plays the same role.)

## Reception status is reset every TC

`Test Setup`(`CDS Test Setup`) checks socket survival and
Empty the accumulated notifications and errors and record the TC start time. There are only some TCs that judge  notifications.
However, the reset is done in the previous TC — If it is emptied only within the judgment TC, the
Notifications remain in the queue and are mistaken for self-results. The connection history is not erased (doing so will cause link diagnosis to be disabled).
becomes impossible).

## Trap — If you are an LTE subscriber, nothing comes.

LTE goes out through RBUS, not SBI ([../../tests/cds/AGENTS.md](../../tests/cds/AGENTS.md) LTE/SA comparison table).
This judgment is based on the premise SA .

# Phone Mirror Toolkit

Mirror and control an Android phone from Windows over ADB -- **including wireless
pairing by QR code**, which `adb` itself cannot do.

```
  +----------------+          scan          +------------------+
  |  PC: QR code   |  <-------------------  |  Android phone   |
  |  pair server   |  TLS + protobuf pair   |  Wireless debug  |
  +--------+-------+  --------------------> +------------------+
           |                                        |
           +----------- scrcpy mirror <-------------+
```

## Why this exists

Google's `adb` has **no built-in QR pairing**:

```
$ adb pair --qr        ->  "No pairing code provided"     (flag not recognised)
$ adb qr               ->  "unknown command qr"
$ strings adb.exe | grep WIFI:T:ADB   ->  (nothing)
```

The latest platform-tools downloaded from Google is byte-for-byte identical to
the one bundled here, so upgrading does not help.

So this toolkit **implements the pairing server itself** -- a Python TLS endpoint
that speaks adb's pairing protocol, renders a QR code, and hands the device to
`scrcpy` once the phone scans it.

## Quick start

```powershell
# 1. clone or download, then:
powershell -ExecutionPolicy Bypass -File install.ps1
```

This copies the toolkit to `%USERPROFILE%\Tools\PhoneMirror`, installs the
Python dependencies, and drops two shortcuts on your desktop.

**Requirements**

- Windows 10/11
- [Python 3.x](https://www.python.org/) -- only for QR pairing; USB mirroring works without it
- Phone with **Developer options -> USB debugging** enabled

## Usage

### Scan to mirror (no cables, no typing codes)

1. Run `Scan to Mirror.bat` -- a QR window opens on the PC
2. On the phone: **Settings -> Developer options -> Wireless debugging ->
   Pair device with QR code**
3. Point the phone at the QR -- it pairs, connects and mirrors automatically

### Mirror an already-paired device

```powershell
.\core\mirror.ps1                 # default 1280px
.\core\mirror.ps1 -MaxSize 1920 -Fullscreen
.\core\mirror.ps1 -MaxSize 1024 -MaxFps 30 -NoAudio   # low latency
.\core\mirror.ps1 -List           # show connected devices
```

### Fallback: manual pairing code

If QR pairing is unavailable, the classic flow still works:

```
phone: Wireless debugging -> Pair device with pairing code
       -> shows a 6-digit code and an IP:port

adb pair <ip>:<port> <6-digit-code>     # code expires in ~1 minute -- be quick
adb connect <ip>:<connect-port>         # port shown on the Wireless debugging screen
```

## Controls while mirroring

| Input | Action |
|---|---|
| Left click | tap |
| Right click | back |
| Middle click | home |
| Scroll wheel | swipe up/down |
| Keyboard | types into the phone |
| Drag an `.apk` onto the window | installs it |

## Layout

```
|-- install.ps1             one-shot installer
|-- core
|   |-- mirror.ps1          mirroring front-end
|   |-- scan-mirror.ps1     QR pairing + mirroring
|   |-- pair_server.py      pairing server (TLS + protobuf)
|   |-- pairing.proto       protocol definition
|   |-- pairing_pb2.py      generated protobuf bindings
|   |-- gen_pair_qr.py      standalone QR generator
|-- bin
    |-- platform-tools/     adb
    |-- scrcpy/             scrcpy 4.1
```

## How the pairing protocol works

The QR payload is nested TLV, base64-encoded and wrapped in a Wi-Fi style URI:

```
WIFI:T:ADB;S:<service-name>;P:<password>;;<base64(payload)>

payload:
  outer  type=0  ->  concatenated inner fields
  inner  type=1  ->  service name
  inner  type=2  ->  password      (the phone compares this)
  inner  type=3  ->  port          (the phone dials this)

each field:  bytes([type]) + struct.pack('>H', len(value)) + value
```

Handshake, once the phone scans:

```
1. phone connects TCP  <pc-ip>:<port>
2. TLS handshake (self-signed cert, generated with `cryptography`)
3. phone -> 4-byte big-endian length + protobuf(PairingPacket.init.pairing_code)
4. server verifies the code, replies with
   4-byte length + protobuf(PairingPacket.result.success = true)
5. server runs `adb connect` to attach the transport
```

Verified against a simulated client:

```
server: READY  CERT_OK  PEER=127.0.0.1  TLS_OK  PACKET=init
        CODE_MATCH=True  SENT_RESULT=True
client: TLS_OK cipher=TLS_AES_256_GCM_SHA384
        SENT_INIT bytes=16
        RESULT=True  PASS
```

## Status

| Feature | State |
|---|---|
| USB / already-paired mirroring | working |
| Toolkit runs standalone from `bin/` | working |
| Installer | working |
| Pairing server: TLS + protobuf | working (simulated client) |
| QR generation | working |
| Manual pairing code flow | working (real device) |
| **QR flow on a real phone** | **not yet verified end-to-end** |

## Gotchas worth knowing

- **PowerShell 5.1 reads UTF-8-without-BOM `.ps1` as ANSI** -- non-ASCII strings
  turn into mojibake and break quoting. Keep these scripts pure ASCII, or save
  them as UTF-8 **with** BOM.
- **Two ADB daemons race on port 5037.** scrcpy ships its own `adb.exe`; set
  `$env:ADB` to the platform-tools one before launching, or connections fail
  intermittently.
- **Duplicate transports break scrcpy** with `more than one device/emulator`.
  Disconnect the redundant one first.
- **A PowerShell array built from a pipeline can collapse to a scalar** -- a
  device name like `adb-XXXX._adb-tls-connect._tcp` silently becomes its first
  character. Build it with `ArrayList` and return `,$arr.ToArray()`.
- **`Start-Process` fails when `NO_PROXY` and `no_proxy` both exist** in the
  environment (`Item has already been added`). Use `Start-Job` instead.
- **The wireless pairing port rotates per attempt**; a stale port returns
  `protocol fault (couldn't read status message)`.

## Credits

Bundles [scrcpy](https://github.com/Genymobile/scrcpy) (Apache-2.0) and
Android platform-tools (Apache-2.0). See `bin/scrcpy/LICENSE.txt` and
`bin/platform-tools/NOTICE.txt`.

## License

MIT -- see `LICENSE`.
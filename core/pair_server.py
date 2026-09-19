# -*- coding: utf-8 -*-
# adb wireless pairing server -- full AOSP pairing protocol (TLS + protobuf)
import os, sys, ssl, socket, struct, base64, secrets, tempfile, subprocess, datetime
import pairing_pb2

HERE = os.path.dirname(os.path.abspath(__file__))
ADB  = os.path.join(HERE, 'bin', 'platform-tools', 'adb.exe')
OUT  = os.path.join(HERE, 'pair-qr.png')

def make_cert(tmpdir):
    from cryptography import x509
    from cryptography.x509.oid import NameOID
    from cryptography.hazmat.primitives import hashes, serialization
    from cryptography.hazmat.primitives.asymmetric import rsa

    key = rsa.generate_private_key(public_exponent=65537, key_size=2048)
    name = x509.Name([x509.NameAttribute(NameOID.COMMON_NAME, u'adb')])
    now = datetime.datetime.utcnow()
    cert = (x509.CertificateBuilder()
            .subject_name(name).issuer_name(name)
            .public_key(key.public_key())
            .serial_number(x509.random_serial_number())
            .not_valid_before(now - datetime.timedelta(days=1))
            .not_valid_after(now + datetime.timedelta(days=2))
            .sign(key, hashes.SHA256()))

    kp = os.path.join(tmpdir, 'k.pem')
    cp = os.path.join(tmpdir, 'c.pem')
    with open(kp, 'wb') as f:
        f.write(key.private_bytes(serialization.Encoding.PEM,
                serialization.PrivateFormat.TraditionalOpenSSL,
                serialization.NoEncryption()))
    with open(cp, 'wb') as f:
        f.write(cert.public_bytes(serialization.Encoding.PEM))
    return kp, cp

def tlv(t, v):
    return bytes([t]) + struct.pack('>H', len(v)) + v

def build_qr_payload(service_name, password, port):
    inner = tlv(1, service_name.encode()) + tlv(2, password.encode()) + tlv(3, str(port).encode())
    return tlv(0, inner)

def local_ip():
    s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    try:
        s.connect(('8.8.8.8', 80)); return s.getsockname()[0]
    except Exception:
        return '0.0.0.0'
    finally:
        s.close()

def make_qr(data, path):
    import qrcode
    qr = qrcode.QRCode(error_correction=qrcode.constants.ERROR_CORRECT_L, box_size=10, border=2)
    qr.add_data(data); qr.make(fit=True)
    qr.make_image(fill_color='black', back_color='white').save(path)

def main():
    name = sys.argv[1] if len(sys.argv) > 1 else 'adb-' + secrets.token_hex(5)
    pw   = sys.argv[2] if len(sys.argv) > 2 else secrets.token_hex(6)
    port = int(sys.argv[3]) if len(sys.argv) > 3 else 0

    srv = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    srv.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    srv.bind(('0.0.0.0', port))
    port = srv.getsockname()[1]
    srv.listen(1)

    payload = build_qr_payload(name, pw, port)
    b64 = base64.b64encode(payload).decode()
    uri = 'WIFI:T:ADB;S:' + name + ';P:' + pw + ';;' + b64
    try:
        make_qr(uri, OUT)
    except Exception as e:
        print('QR_FAIL ' + str(e), flush=True)

    print('SERVICE_NAME=' + name, flush=True)
    print('PASSWORD=' + pw, flush=True)
    print('PORT=' + str(port), flush=True)
    print('URI=' + uri, flush=True)
    print('PNG=' + OUT, flush=True)
    print('IP=' + local_ip(), flush=True)
    print('READY', flush=True)

    tmpdir = tempfile.mkdtemp()
    try:
        key, crt = make_cert(tmpdir)
        print('CERT_OK', flush=True)
    except Exception as e:
        print('CERT_FAIL ' + str(e), flush=True)
        return 1

    ctx = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
    ctx.load_cert_chain(crt, key)
    ctx.check_hostname = False
    ctx.verify_mode = ssl.CERT_NONE

    srv.settimeout(180)
    try:
        conn, addr = srv.accept()
    except socket.timeout:
        print('TIMEOUT', flush=True); return 2

    print('PEER=' + addr[0], flush=True)
    try:
        tls = ctx.wrap_socket(conn, server_side=True)
    except Exception as e:
        print('TLS_FAIL ' + str(e), flush=True); return 3

    print('TLS_OK', flush=True)
    hdr = tls.recv(4)
    if len(hdr) < 4:
        print('HANDSHAKE_SHORT', flush=True); return 4
    n = struct.unpack('>I', hdr)[0]
    body = b''
    while len(body) < n:
        chunk = tls.recv(n - len(body))
        if not chunk: break
        body += chunk

    pkt = pairing_pb2.PairingPacket()
    pkt.ParseFromString(body)
    which = pkt.WhichOneof('packet')
    print('PACKET=' + str(which), flush=True)

    ok = False
    if which == 'init':
        got = pkt.init.pairing_code.decode(errors='replace')
        ok = (got == pw)
        print('CODE_MATCH=' + str(ok), flush=True)

    resp = pairing_pb2.PairingPacket()
    resp.result.success = ok
    rb = resp.SerializeToString()
    tls.sendall(struct.pack('>I', len(rb)) + rb)
    print('SENT_RESULT=' + str(ok), flush=True)

    if ok:
        subprocess.run([ADB, 'connect', local_ip() + ':' + str(port)], capture_output=True)
        print('PAIRED_OK', flush=True)
    tls.close()
    return 0

if __name__ == '__main__':
    sys.exit(main())
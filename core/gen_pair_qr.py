# -*- coding: utf-8 -*-
import os
import sys, os, socket, struct, base64, string, random
import qrcode

def tlv(t, v):
    return bytes([t]) + struct.pack('>H', len(v)) + v

def make_payload(service_name, password, port):
    body = b''.join([
        tlv(1, service_name.encode()),
        tlv(2, password.encode()),
        tlv(3, str(port).encode()),
    ])
    return tlv(0, body)

def local_ip():
    s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    try:
        s.connect(('8.8.8.8', 80))
        return s.getsockname()[0]
    except Exception:
        return '0.0.0.0'
    finally:
        s.close()

def rand_str(n=10):
    return ''.join(random.choice(string.ascii_letters + string.digits) for _ in range(n))

name = sys.argv[1] if len(sys.argv) > 1 else 'adb-' + rand_str()
pw   = sys.argv[2] if len(sys.argv) > 2 else rand_str(12)
port = int(sys.argv[3]) if len(sys.argv) > 3 else 0
out  = sys.argv[4] if len(sys.argv) > 4 else os.path.join(os.path.dirname(os.path.abspath(__file__)), 'pair-qr.png')

if port == 0:
    s = socket.socket()
    s.bind(('', 0))
    port = s.getsockname()[1]
    s.close()

payload = make_payload(name, pw, port)
b64 = base64.b64encode(payload).decode()
uri = 'WIFI:T:ADB;S:' + name + ';P:' + pw + ';;' + b64

qr = qrcode.QRCode(error_correction=qrcode.constants.ERROR_CORRECT_L, box_size=10, border=2)
qr.add_data(uri)
qr.make(fit=True)
img = qr.make_image(fill_color='black', back_color='white')
img.save(out)

print('SERVICE_NAME=' + name)
print('PASSWORD=' + pw)
print('PORT=' + str(port))
print('URI=' + uri)
print('PNG=' + out)
print('IP=' + local_ip())
import sys
from cryptography import x509
from cryptography.hazmat.primitives import serialization
d,o=sys.argv[1],sys.argv[2]
ark=x509.load_pem_x509_certificate(open(d+'/ark.pem','rb').read())
ask=x509.load_pem_x509_certificate(open(d+'/ask.pem','rb').read())
vcek=x509.load_der_x509_certificate(open(d+'/vcek_milan.der','rb').read())
w=lambda n,b: open(f'{o}/{n}.bin','wb').write(b)
w('ark_n', ark.public_key().public_numbers().n.to_bytes(512,'big'))
w('ask_n', ask.public_key().public_numbers().n.to_bytes(512,'big'))
w('ask_tbs', ask.tbs_certificate_bytes); w('ask_sig', ask.signature)
w('vcek_tbs', vcek.tbs_certificate_bytes); w('vcek_sig', vcek.signature)
pub=vcek.public_key().public_bytes(serialization.Encoding.X962, serialization.PublicFormat.UncompressedPoint)
assert pub[0]==4; w('vcek_pub', pub[1:])
r=bytes.fromhex(open(d+'/report_milan.hex').read().strip())
w('report_signed', r[:0x2A0])
R=r[0x2A0:0x2A0+72][::-1][-48:]; S=r[0x2E8:0x2E8+72][::-1][-48:]
assert r[0x2A0+48:0x2A0+72]==bytes(24) and r[0x2E8+48:0x2E8+72]==bytes(24)
w('report_sig', R+S); print('ok', len(ask.signature), len(vcek.signature))

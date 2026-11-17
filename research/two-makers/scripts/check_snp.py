import sys,hashlib
from cryptography import x509
from cryptography.hazmat.primitives import hashes, serialization
from cryptography.hazmat.primitives.asymmetric import padding, ec
from cryptography.hazmat.primitives.asymmetric.utils import encode_dss_signature
d=sys.argv[1]
ark=x509.load_pem_x509_certificate(open(d+'/ark.pem','rb').read())
ask=x509.load_pem_x509_certificate(open(d+'/ask.pem','rb').read())
vcek=x509.load_der_x509_certificate(open(d+'/vcek_milan.der','rb').read())
def pss(parent,child):
    parent.public_key().verify(child.signature, child.tbs_certificate_bytes,
        padding.PSS(mgf=padding.MGF1(hashes.SHA384()), salt_length=48), hashes.SHA384())
pss(ark,ark); pss(ark,ask); pss(ask,vcek)
print('ARK sha256', hashlib.sha256(ark.public_bytes(serialization.Encoding.DER)).hexdigest())
print('ARK', ark.subject.rfc4514_string(), ark.public_key().key_size,'bit RSA; valid to', ark.not_valid_after_utc.date())
print('ASK', ask.subject.rfc4514_string(), ask.public_key().key_size)
print('VCEK', vcek.subject.rfc4514_string(), vcek.public_key().curve.name, 'valid to', vcek.not_valid_after_utc.date())
print('chain ok: ARK -> ASK -> VCEK (RSA-PSS SHA-384)')
r=bytes.fromhex(open(d+'/report_milan.hex').read().strip())
assert len(r)==1184
ver=int.from_bytes(r[0:4],'little'); algo=int.from_bytes(r[0x34:0x38],'little')
R=int.from_bytes(r[0x2A0:0x2A0+72],'little'); S=int.from_bytes(r[0x2E8:0x2E8+72],'little')
vcek.public_key().verify(encode_dss_signature(R,S), r[:0x2A0], ec.ECDSA(hashes.SHA384()))
print('report v%d, signature algo %d: signature ok (P-384), signed part %d bytes'%(ver,algo,0x2A0))
print('report_data (64 bytes) at 0x50:', r[0x50:0x90].hex()[:32]+'...')
print('measurement (48 bytes) at 0x90:', r[0x90:0xC0].hex()[:32]+'...')
print('reported TCB at 0x180:', r[0x180:0x188].hex(), ' chip id at 0x1A0:', r[0x1A0:0x1E0].hex()[:16]+'...')

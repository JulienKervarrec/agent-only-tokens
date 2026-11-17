import sys,cbor2,hashlib,datetime
from cryptography import x509
from cryptography.hazmat.primitives.asymmetric import ec
from cryptography.hazmat.primitives import hashes
from cryptography.hazmat.primitives.asymmetric.utils import encode_dss_signature
raw=open(sys.argv[1],'rb').read()
prot,unprot,payload,sig=cbor2.loads(raw)
doc=cbor2.loads(payload)
certs=[x509.load_der_x509_certificate(c) for c in doc['cabundle']]+[x509.load_der_x509_certificate(doc['certificate'])]
root=certs[0]
print('root sha256', hashlib.sha256(root.public_bytes(__import__('cryptography.hazmat.primitives.serialization',fromlist=['x']).Encoding.DER)).hexdigest())
print('root subject', root.subject.rfc4514_string())
for parent,child in zip(certs,certs[1:]):
    parent.public_key().verify(child.signature, child.tbs_certificate_bytes, ec.ECDSA(child.signature_hash_algorithm))
print('chain ok:', len(certs),'certs')
tbs=cbor2.dumps(['Signature1',prot,b'',payload])
r=int.from_bytes(sig[:48],'big'); s=int.from_bytes(sig[48:],'big')
certs[-1].public_key().verify(encode_dss_signature(r,s), tbs, ec.ECDSA(hashes.SHA384()))
print('document signature ok (P-384)')
ts=datetime.datetime.fromtimestamp(doc['timestamp']/1000, datetime.UTC)
print('timestamp', ts.isoformat(), 'leaf valid', certs[-1].not_valid_before_utc.isoformat(), '->', certs[-1].not_valid_after_utc.isoformat())
print('module', doc['module_id'], 'digest', doc['digest'])
print('pcrs set:', [k for k,v in doc['pcrs'].items() if any(v)], 'pcr len', len(doc['pcrs'][0]))
print('user_data len', len(doc['user_data'] or b''), 'nonce', doc['nonce'] is not None, 'public_key len', len(doc['public_key'] or b''))

"""Generate deterministic count workloads with changing densities; run pairs sequentially."""
from pathlib import Path
import hashlib,json,subprocess
s=Path(__file__).resolve().parent
corpora=s/'corpora';corpora.mkdir(exist_ok=True)
def line(hit=b''):
 return (b'INFO '+hit+b' ').ljust(127,b'x')+b'\n'
plain=line();hit=line(b'rare-needle rare-needle')
block_size=16*1024*1024
sparse=(hit+plain*1023)*(block_size//(128*1024))
dense=hit*(block_size//128)
profiles={
 'sparse-then-dense':sparse+dense,
 'dense-then-sparse':dense+sparse,
 'one-in-eight':(hit+plain*7)*(2*block_size//1024),
 'rejected-words':line(b'rare-needlex rare-needlex')*(2*block_size//128),
 'empty-then-rejected':(b'INFO '.ljust(127,b'x')+b'\n')*(block_size//128)+line(b'rare-needlex rare-needlex')*(block_size//128),
 'long-lines':((b'INFO '+b'rare-needle '*(1024*1024//12))[:1024*1024]+b'\n')*32,
}
metadata={}
for name,data in profiles.items():
 p=corpora/(name+'.txt');p.write_bytes(data)
 metadata[name]={'bytes':len(data),'lines':data.count(b'\n'),'sha256':hashlib.sha256(data).hexdigest()}
(s/'corpora.json').write_text(json.dumps(metadata,indent=2)+'\n')

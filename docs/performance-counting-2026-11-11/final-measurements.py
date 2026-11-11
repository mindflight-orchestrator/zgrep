"""Run the final benchmark sessions serially, never alongside builds/tests."""
import subprocess
from pathlib import Path
s=Path(__file__).resolve().parent
base=['python3',str(s/'compare-count.py'),'--baseline',str(s/'baseline/bin/zgr'),'--candidate',str(s/'candidate2/bin/zgr'),'--corpus','/tmp/zgrep-backends-20261111-3ahjbzi8/publication/corpus.txt','--repeats','25']
commands=[
 ('final-auto',base+['--suite','full','--output',str(s/'final-auto.json')]),
 ('final-text',base+['--suite','focused','--input-mode','text','--output',str(s/'final-text.json')]),
 ('final-four-core',base+['--suite','focused','--cpu','2,4,6,8','--repeats','15','--output',str(s/'final-four-core.json')]),
 ('final-micro',['python3','/home/dlamotte/Documents/mindflight/zgrep/bench/internal.py','--library',str(s/'candidate2/lib/libzgrep-internal-bench.so'),'--baseline-library',str(s/'baseline/lib/libzgrep-internal-bench.so'),'--corpus','/tmp/zgrep-backends-20261111-3ahjbzi8/publication/corpus.txt','--cpu','2','--repeats','25','--output',str(s/'final-micro.json')]),
]
for profile in ['sparse-then-dense','dense-then-sparse','one-in-eight','rejected-words','long-lines','empty-then-rejected']:
 name='final-'+profile
 commands.append((name,base+['--corpus',str(s/'corpora'/(profile+'.txt')),'--suite','counts','--repeats','11','--output',str(s/(name+'.json'))]))
for name,cmd in commands:
 with (s/(name+'.log')).open('w') as log:subprocess.run(cmd,stdout=log,stderr=subprocess.STDOUT,check=True)
 print(name,'passed',flush=True)

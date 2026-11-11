"""Large newline/NUL record checks on both engines and four CPUs."""
from pathlib import Path
import hashlib,json,os,subprocess
s=Path(__file__).resolve().parent
os.sched_setaffinity(0,{2,4,6,8})
text=Path('/tmp/zgrep-backends-20261111-3ahjbzi8/publication/corpus.txt')
nul=s/'corpora/records-nul.dat';nul.write_bytes(text.read_bytes().replace(b'\n',b'\0'))
flags=[['-F','-c','rare-needle'],['-F','-i','-c','RARE-NEEDLE'],['-F','-w','-c','rare-needle'],['-F','-v','-c','rare-needle'],['-F','-c','INFO'],['-F','-v','-c','INFO'],['-F','-c',''],['-F','-w','-c',''],['-F','-c','a'*32],['-F','-c','a'*33],['-F','-x','-c','rare-needle']]
r={'status':'incomplete','cpu':sorted(os.sched_getaffinity(0)),'cases':[],'checks':0,'corpora':{str(p):hashlib.sha256(p.read_bytes()).hexdigest() for p in [text,nul]}}
env=dict(os.environ,LC_ALL='C')
for corpus,extra in [(text,[]),(nul,['-z'])]:
 for options in flags:
  expected=subprocess.run(['/usr/bin/grep',*extra,*options,str(corpus)],capture_output=True,env=env)
  assert expected.returncode in (0,1) and not expected.stderr
  for engine in ['zgr','zgrc']:
   cmd=[str(s/'qualified/bin'/engine),*extra,*options,str(corpus)]
   actual=subprocess.run(cmd,capture_output=True,env=env)
   assert (actual.returncode,actual.stdout,actual.stderr)==(expected.returncode,expected.stdout,expected.stderr),(engine,extra,options,actual,expected)
   r['checks']+=1;r['cases'].append({'command':cmd,'status':actual.returncode,'stdout':actual.stdout.decode(),'stderr':''})
r['status']='passed';(s/'records.json').write_text(json.dumps(r,indent=2)+'\n');print(r['checks'],'large-record checks passed',flush=True)

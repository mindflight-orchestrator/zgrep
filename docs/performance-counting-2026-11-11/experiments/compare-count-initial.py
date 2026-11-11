"""Paired performance probe for adaptive literal counting; always checks GNU output."""
import argparse,hashlib,importlib.util,json,os,random,shutil,statistics,subprocess,sys,tempfile
from pathlib import Path
sys.dont_write_bytecode=True
p=argparse.ArgumentParser()
p.add_argument('--candidate',type=Path,required=True)
p.add_argument('--baseline',type=Path,required=True)
p.add_argument('--corpus',type=Path,required=True)
p.add_argument('--output',type=Path,required=True)
p.add_argument('--root',type=Path,default=Path('/home/dlamotte/Documents/mindflight/zgrep'))
p.add_argument('--cpu',default='2')
p.add_argument('--repeats',type=int,default=15)
p.add_argument('--suite',choices=['focused','full'],default='focused')
p.add_argument('--input-mode',choices=['auto','text'],default='auto')
a=p.parse_args()
assert a.repeats>0 and not a.output.exists()
spec=importlib.util.spec_from_file_location('comparison',a.root/'bench/compare.py');mod=importlib.util.module_from_spec(spec);spec.loader.exec_module(mod)
os.sched_setaffinity(0,{int(v) for v in a.cpu.split(',')})
tools={'baseline':a.baseline.resolve(),'candidate':a.candidate.resolve(),'ripgrep':Path(shutil.which('rg')),'grep':Path(shutil.which('grep'))}
versions={k:subprocess.check_output([v,'--version'],text=True) for k,v in tools.items()}
for k in ['baseline','candidate']:assert 'optimize=ReleaseFast backend=stage2_llvm' in versions[k]
cases=mod.CASES
if a.suite=='focused':cases=[c for c in cases if c[0] in ['literal miss','rare literal','case insensitive','word literal','dense literal','sparse numbered','dense plain']]
cases=cases+[('inverted rare',['-F','-v','-c','rare-needle'],[]),('inverted dense',['-F','-v','-c','INFO'],[])]
r={'status':'incomplete','runner_sha256':mod.sha256(Path(__file__)),'comparator_sha256':mod.sha256(a.root/'bench/compare.py'),'source_commit':subprocess.check_output(['git','rev-parse','HEAD'],cwd=a.root,text=True).strip(),'cpu':sorted(os.sched_getaffinity(0)),'corpus':{'path':str(a.corpus),'sha256':mod.sha256(a.corpus),'bytes':a.corpus.stat().st_size},'tools':{k:{'path':str(v),'sha256':mod.sha256(v),'version':versions[k]} for k,v in tools.items()},'repeats':a.repeats,'warmups':2,'seed':712,'input_mode':a.input_mode,'locale':'C','sink':'regular file without fsync','includes_process_startup':True,'checks':0,'cases':[]}
with a.output.open('x') as out:json.dump(r,out,indent=2)
env=dict(os.environ,LC_ALL='C',GREP_COLORS='');env.pop('RIPGREP_CONFIG_PATH',None);rng=random.Random(r['seed'])
try:
 with tempfile.TemporaryDirectory() as tmp:
  sink=Path(tmp)/'out'
  for name,flags,extra in cases:
   add=['-a'] if a.input_mode=='text' else []
   commands={k:[str(v),*add,*flags,str(a.corpus)] for k,v in tools.items()}
   commands['ripgrep']=[str(tools['ripgrep']),'--no-config','--color=never',*add,*extra,*(f for f in flags if f!='-E'),str(a.corpus)]
   _,expected=mod.measure(commands['grep'],sink,env)
   samples={k:[] for k in tools};orders=[]
   for n in range(-2,a.repeats):
    order=list(tools);rng.shuffle(order);orders.append(order)
    for k in order:
     elapsed,actual=mod.measure(commands[k],sink,env);assert actual==expected,(name,k,actual,expected)
     r['checks']+=1
     if n>=0:samples[k].append(elapsed)
   ratios=[x/y for x,y in zip(samples['baseline'],samples['candidate'])]
   br=random.Random(712);bs=sorted(statistics.median(br.choices(ratios,k=len(ratios))) for _ in range(5000))
   row={'name':name,'commands':commands,'expected':expected,'samples_ms':samples,'orders':orders,'median_ms':{k:statistics.median(v) for k,v in samples.items()},'baseline_over_candidate':{'median_paired_ratio':statistics.median(ratios),'bootstrap95':[bs[125],bs[4874]]}}
   r['cases'].append(row);a.output.write_text(json.dumps(r,indent=2)+'\n');print(name,row['median_ms'],row['baseline_over_candidate'],flush=True)
 r['status']='passed'
except Exception as error:
 r['status']='failed';r['error']=str(error);raise
finally:a.output.write_text(json.dumps(r,indent=2)+'\n')
print('checks',r['checks'],flush=True)

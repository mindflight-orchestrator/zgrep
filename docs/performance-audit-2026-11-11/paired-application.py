"""Paired application audit; archival runner with explicit baseline and candidate paths."""
import argparse,hashlib,importlib.util,json,os,random,shutil,statistics,subprocess,tempfile,time
from pathlib import Path
p=argparse.ArgumentParser();p.add_argument('--output',type=Path,required=True);p.add_argument('--cpu',default='2');p.add_argument('--repeats',type=int,default=15);args=p.parse_args()
root=Path('/home/dlamotte/Documents/mindflight/zgrep');r=Path(__file__).resolve().parent
spec=importlib.util.spec_from_file_location('comparison',root/'bench/compare.py');module=importlib.util.module_from_spec(spec);spec.loader.exec_module(module)
os.sched_setaffinity(0,{int(i) for i in args.cpu.split(',')})
corpus=Path('/tmp/zgrep-backends-20261111-3ahjbzi8/publication/corpus.txt')
tools={'baseline':Path('/tmp/zgrep-backends-20261111-3ahjbzi8/publication/out/bin/zgr'),'candidate':r/'qualified/bin/zgr','zgrc':r/'qualified/bin/zgrc','ripgrep':Path(shutil.which('rg')),'grep':Path(shutil.which('grep'))}
result={'status':'incomplete','runner_sha256':module.sha256(Path(__file__)), 'source_inputs_sha256':{str(p.relative_to(root)):module.sha256(p) for p in [root/'build.zig',root/'build.zig.zon',*sorted((root/'src').glob('*')),*sorted((root/'include').glob('*'))] if p.is_file()},'source_commit':subprocess.check_output(['git','rev-parse','HEAD'],cwd=root,text=True).strip(),'cpu':sorted(os.sched_getaffinity(0)),'corpus_sha256':module.sha256(corpus),'tools':{name:{'path':str(path),'sha256':module.sha256(path),'version':subprocess.check_output([path,'--version'],text=True)} for name,path in tools.items()},'repeats':args.repeats,'warmups':2,'seed':711,'locale':'C','sink':'regular file without fsync','checks':0,'cases':[]}
with args.output.open('x') as output:json.dump(result,output,indent=2)
env=dict(os.environ,LC_ALL='C',GREP_COLORS='');env.pop('RIPGREP_CONFIG_PATH',None);rng=random.Random(711)
try:
 with tempfile.TemporaryDirectory() as tmp:
  sink=Path(tmp)/'out'
  for mode in ['auto','text']:
   for name,flags,extra in module.CASES:
    if mode=='text' and name not in ['literal miss','rare literal','case insensitive','word literal','dense literal','sparse numbered']:continue
    add=['-a'] if mode=='text' else []
    commands={tool:[str(binary),*add,*flags,str(corpus)] for tool,binary in tools.items()}
    commands['ripgrep']=[str(tools['ripgrep']),'--no-config','--color=never',*add,*extra,*(x for x in flags if x!='-E'),str(corpus)]
    _,expected=module.measure(commands['grep'],sink,env)
    samples={tool:[] for tool in tools};orders=[]
    for _ in range(args.repeats+2):
     order=list(tools);rng.shuffle(order);orders.append(order)
     for tool in order:
      elapsed,actual=module.measure(commands[tool],sink,env)
      assert actual==expected,(mode,name,tool,actual,expected)
      result['checks']+=1
      if _>=2:samples[tool].append(elapsed)
    row={'mode':mode,'name':name,'commands':commands,'expected':expected,'samples_ms':samples,'orders':orders,'median_ms':{k:statistics.median(v) for k,v in samples.items()}}
    ratios=[a/b for a,b in zip(samples['baseline'],samples['candidate'])];br=random.Random(711);boots=sorted(statistics.median(br.choices(ratios,k=len(ratios))) for _ in range(2000))
    row['baseline_over_candidate']={'median_paired_ratio':statistics.median(ratios),'bootstrap_95_percent':[boots[50],boots[1949]]}
    result['cases'].append(row);args.output.write_text(json.dumps(result,indent=2)+'\n');print(mode,name,row['median_ms'],flush=True)
 result['status']='passed'
except Exception as err:
 result['status']='failed';result['error']=str(err);raise
finally:args.output.write_text(json.dumps(result,indent=2)+'\n')
print('passed',result['checks'])

import hashlib,importlib.util,json,os,random,shutil,statistics,subprocess,tempfile
from pathlib import Path
r=Path(__file__).resolve().parent;repo=Path('/home/dlamotte/Documents/mindflight/zgrep')
spec=importlib.util.spec_from_file_location('comparison',repo/'bench/compare.py');m=importlib.util.module_from_spec(spec);spec.loader.exec_module(m)
corpus=Path('/tmp/zgrep-backends-20261111-3ahjbzi8/publication/corpus.txt')
tools={'baseline':Path('/tmp/zgrep-backends-20261111-3ahjbzi8/publication/out/bin/zgr'),'candidate':r/'final/bin/zgr','ripgrep':Path(shutil.which('rg')),'grep':Path(shutil.which('grep'))}
cases=[c for c in m.CASES if c[0] in ['literal miss','rare literal','case insensitive','word literal','dense literal','sparse numbered']]
result={'status':'incomplete','corpus_sha256':m.sha256(corpus),'tools':{k:{'path':str(v),'sha256':m.sha256(v)} for k,v in tools.items()},'repeats':25,'warmups':2,'seed':123,'checks':0,'cases':[]}
out=r/'confirmation.json';out.open('x').close();rng=random.Random(123);env=dict(os.environ,LC_ALL='C',GREP_COLORS='')
try:
 with tempfile.TemporaryDirectory() as tmp:
  sink=Path(tmp)/'output'
  for cpus in [[2],[2,4,6,8]]:
   os.sched_setaffinity(0,set(cpus))
   for mode in ['auto','text']:
    for name,flags,extra in cases:
     if len(cpus)==1 and name!='dense literal':continue
     add=['-a'] if mode=='text' else []
     commands={k:[str(v),*add,*flags,str(corpus)] for k,v in tools.items()}
     commands['ripgrep']=[str(tools['ripgrep']),'--no-config','--color=never',*add,*extra,*(x for x in flags if x!='-E'),str(corpus)]
     _,expected=m.measure(commands['grep'],sink,env);samples={k:[] for k in tools}
     for n in range(27):
      order=list(tools);rng.shuffle(order)
      for tool in order:
       elapsed,actual=m.measure(commands[tool],sink,env);assert actual==expected,(name,tool)
       result['checks']+=1
       if n>=2:samples[tool].append(elapsed)
     ratios=[a/b for a,b in zip(samples['baseline'],samples['candidate'])];br=random.Random(123);bs=sorted(statistics.median(br.choices(ratios,k=25)) for _ in range(2000))
     row={'cpu':cpus,'mode':mode,'name':name,'samples_ms':samples,'median_ms':{k:statistics.median(v) for k,v in samples.items()},'baseline_over_candidate':{'median_paired_ratio':statistics.median(ratios),'bootstrap_95_percent':[bs[50],bs[1949]]}}
     result['cases'].append(row);out.write_text(json.dumps(result,indent=2)+'\n');print(cpus,mode,name,row['median_ms'],row['baseline_over_candidate'],flush=True)
 result['status']='passed'
except Exception as err:result['status']='failed';result['error']=str(err);raise
finally:out.write_text(json.dumps(result,indent=2)+'\n')

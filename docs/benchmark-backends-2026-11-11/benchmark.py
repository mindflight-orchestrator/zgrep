import hashlib,json,os,random,statistics,subprocess,time
from pathlib import Path
r=Path(__file__).resolve().parent
env=dict(os.environ,LC_ALL='C',GREP_COLORS='')
cpu=2 if 2 in os.sched_getaffinity(0) else min(os.sched_getaffinity(0))
os.sched_setaffinity(0,{cpu})
corpus=r/'corpus.txt'
cases=[
 ('literal miss',['-F','-c','not-present-anywhere']),
 ('rare literal',['-F','-c','rare-needle']),
 ('case insensitive',['-F','-i','-c','RARE-NEEDLE']),
 ('word literal',['-F','-w','-c','rare-needle']),
 ('dense regex',['-E','-c','status=(200|500)']),
 ('regex suffix',['-E','-c','[a-z]+-needle']),
 ('alternation',['-E','-c','rare-needle|status=500|route=/api/item/42|latency_us=999']),
 ('regex no literal',['-E','-c','[[:alnum:]_]{4}[[:space:]]+[[:alnum:]_]{7}']),
 ('sparse numbered',['-F','-n','rare-needle']),
 ('dense numbered',['-F','-n','INFO']),
]
builds=json.loads((r/'build-results.json').read_text())
variants=[b['variant'] for b in builds if b['status']==0]
results={'cpu':cpu,'repeats':15,'seed':711,'corpus_bytes':corpus.stat().st_size,'corpus_sha256':hashlib.sha256(corpus.read_bytes()).hexdigest(),'variants':variants,'cases':[],'binaries':{},'failures':[]}
rng=random.Random(711)
for variant in variants:
 for tool in ['zgr','zgrc']:
  p=r/variant/'out/bin'/tool
  results['binaries'][variant+'/'+tool]={'bytes':p.stat().st_size,'sha256':hashlib.sha256(p.read_bytes()).hexdigest()}
def once(binary,args):
 path=r/'output.tmp'
 with path.open('wb') as out:
  t=time.perf_counter_ns()
  p=subprocess.run([str(binary),*args,str(corpus)],stdout=out,stderr=subprocess.PIPE,env=env,timeout=30)
  ms=(time.perf_counter_ns()-t)/1e6
 return ms,p.returncode,hashlib.sha256(path.read_bytes()).hexdigest(),p.stderr.decode(errors='replace')
for tool in ['zgr','zgrc']:
 for name,args in cases:
  _,ref_code,ref_hash,_=once('/usr/bin/grep',args)
  samples={v:[] for v in variants}
  valid=[]
  for variant in variants:
   binary=r/variant/'out/bin'/tool
   for warmup in range(2):
    ms,code,sha,stderr=once(binary,args)
    if (code,sha)!=(ref_code,ref_hash):
     results['failures'].append({'tool':tool,'variant':variant,'case':name,'status':code,'stderr':stderr,'sha256':sha,'expected_sha256':ref_hash})
     print('FAIL',tool,variant,name,code,stderr,flush=True)
     break
   else:valid.append(variant)
  for rep in range(results['repeats']):
   order=valid.copy();rng.shuffle(order)
   for variant in order:
    ms,code,sha,stderr=once(r/variant/'out/bin'/tool,args)
    if (code,sha)!=(ref_code,ref_hash):raise RuntimeError((tool,variant,name,code,stderr))
    samples[variant].append(ms)
  row={'tool':tool,'case':name,'args':args,'expected_status':ref_code,'expected_sha256':ref_hash,'samples_ms':samples,'median_ms':{v:statistics.median(x) for v,x in samples.items() if x},'comparisons':{}}
  for baseline,candidate in [('0.16-native','0.16-llvm'),('0.17-native','0.17-llvm'),('0.16-llvm','0.17-llvm'),('0.16-native','0.17-native')]:
   if samples.get(baseline) and samples.get(candidate):
    ratios=[a/b for a,b in zip(samples[baseline],samples[candidate])]
    boot_rng=random.Random(711)
    boots=sorted(statistics.median(boot_rng.choices(ratios,k=len(ratios))) for _ in range(3000))
    row['comparisons'][baseline+'/'+candidate]={'speedup':statistics.median(ratios),'ci95':[boots[75],boots[2924]]}
  results['cases'].append(row)
  (r/'benchmark-results.json').write_text(json.dumps(results,indent=2))
  print(tool,name,' '.join(f'{v}={m:.3f}ms' for v,m in row['median_ms'].items()),flush=True)
print('FINISHED',len(results['cases']),'cases; failures',len(results['failures']),flush=True)

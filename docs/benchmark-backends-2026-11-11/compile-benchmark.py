import hashlib,json,os,random,shlex,statistics,subprocess,time
from pathlib import Path
r=Path(__file__).resolve().parent
variants=['0.16-llvm','0.16-native','0.17-llvm','0.17-native']
results={'method':'3 compilations of zgr per variant, fresh local compiler cache per sample, existing global infrastructure cache, -j2, sequential random order; build runner and translate-c excluded','samples':[]}
commands={}
for variant in variants:
 for line in (r/variant/'build.log').read_text().splitlines():
  if ' build-exe ' in line and ' --name zgr ' in line and not line.startswith('failed'):
   commands[variant]=shlex.split(line.removeprefix('info(verbose): '))
   break
rng=random.Random(711)
for rep in range(3):
 order=variants.copy();rng.shuffle(order)
 for variant in order:
  folder=r/'compile-check'/variant/str(rep);folder.mkdir(parents=True)
  cmd=commands[variant].copy();cmd.remove('--listen=-')
  cmd[cmd.index('--cache-dir')+1]=str(folder/'local-cache')
  cmd.extend(['-j2','-femit-bin='+str(folder/'zgr')])
  start=time.perf_counter()
  with (folder/'compile.log').open('w') as log:p=subprocess.run(cmd,cwd=r/('src-017a' if variant.startswith('0.17') else 'src'),stdout=log,stderr=subprocess.STDOUT,timeout=180)
  row={'variant':variant,'repetition':rep,'seconds':time.perf_counter()-start,'status':p.returncode,'command':cmd}
  if p.returncode==0:row['sha256']=hashlib.sha256((folder/'zgr').read_bytes()).hexdigest()
  results['samples'].append(row)
  (r/'compile-results.json').write_text(json.dumps(results,indent=2))
  print(variant,rep,f'{row["seconds"]:.3f}s',p.returncode,flush=True)
  if p.returncode:raise RuntimeError((folder/'compile.log').read_text())
results['median_seconds']={v:statistics.median(x['seconds'] for x in results['samples'] if x['variant']==v) for v in variants}
(r/'compile-results.json').write_text(json.dumps(results,indent=2))
print(results['median_seconds'],flush=True)

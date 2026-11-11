from pathlib import Path
import hashlib,json,os,subprocess
s=Path(__file__).resolve().parent
for p,digest in json.loads((s/'candidate2-inputs.json').read_text()).items():assert hashlib.sha256(Path(p).read_bytes()).hexdigest()==digest,p
env=dict(os.environ,ZIG_GLOBAL_CACHE_DIR='/tmp/zgrep-backends-20261111-3ahjbzi8/0.16-llvm/global-cache',ZIG_LOCAL_CACHE_DIR='/tmp/zgrep-backends-20261111-3ahjbzi8/publication/local-cache',ZGREP_FUZZ_ITERATIONS='256')
commands=[
 ('qualification-final',['zig-0.16','build','test','test-fuzz','bench-internal','install','-Doptimize=ReleaseFast','-Dllvm=true','--prefix',str(s/'qualified'),'--summary','all']),
 ('qualification-safe',['zig-0.16','build','test-zpcre2','-Doptimize=ReleaseSafe','-Dllvm=true','--summary','all']),
 ('qualification-records',['python3',str(s/'check-records.py')]),
]
for name,cmd in commands:
 with (s/(name+'.log')).open('w') as log:subprocess.run(cmd,stdout=log,stderr=subprocess.STDOUT,env=env,check=True)
 print(name,'passed',flush=True)
for p in ['bin/zgr','bin/zgrc','lib/libzgrep-internal-bench.so']:
 assert (s/'qualified'/p).read_bytes()==(s/'candidate2'/p).read_bytes(),p
print('Qualified artifacts identical to measured candidate2.',flush=True)

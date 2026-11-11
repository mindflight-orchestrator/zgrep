import json,os,subprocess,time
from pathlib import Path
r=Path(__file__).resolve().parent
results=[]
for version in ["0.16","0.17"]:
 for backend in ["llvm","native"]:
  name=version+"-"+backend
  folder=r/name;folder.mkdir(exist_ok=True)
  cmd=["zig-"+version,"build","-Doptimize=ReleaseFast","-Dcpu=native","-Dllvm="+("true" if backend=="llvm" else "false"),"-j2","--prefix",str(folder/"out"),"--cache-dir",str(folder/"local-cache"),"--global-cache-dir",str(folder/"global-cache"),"--summary","all","--verbose"]
  print("BUILD",name,flush=True)
  start=time.perf_counter()
  with (folder/"build.log").open("w") as log:
   try:
    p=subprocess.run(cmd,cwd=r/"src",env=dict(os.environ,ZIG_GLOBAL_CACHE_DIR=str(folder/"global-cache"),ZIG_LOCAL_CACHE_DIR=str(folder/"local-cache")),stdout=log,stderr=subprocess.STDOUT,timeout=240)
    status=p.returncode
   except subprocess.TimeoutExpired:status=124
  row={"variant":name,"command":cmd,"status":status,"seconds":time.perf_counter()-start}
  results.append(row);(r/"build-results.json").write_text(json.dumps(results,indent=2))
  print(json.dumps(row),flush=True)
  if status:print((folder/"build.log").read_text()[-8000:],flush=True)

import json,os,subprocess,statistics
from pathlib import Path
r=Path(__file__).resolve().parent
results={}
for backend in ["llvm","native"]:
 cmd=["zig-0.16","build-obj",str(r/"kernels.zig"),"-OReleaseFast","-mcpu=native","-fllvm" if backend=="llvm" else "-fno-llvm","-femit-bin="+str(r/(backend+".o")),"--cache-dir",str(r/(backend+"-cache")),"--global-cache-dir",str(r.parent/"0.16-llvm/global-cache")]
 subprocess.run(cmd,check=True)
 with (r/(backend+".asm")).open("w") as out:subprocess.run(["objdump","-d","-Mintel",str(r/(backend+".o"))],stdout=out,check=True)
 subprocess.run(["cc","-O3","-no-pie",str(r/"driver.c"),str(r/(backend+".o")),"-o",str(r/backend)],check=True)
 output=subprocess.check_output(["taskset","-c","2",str(r/backend)],text=True)
 (r/(backend+".txt")).write_text(output)
 results[backend]={}
 for line in output.splitlines():
  name,*values=line.split();nums=list(map(float,values));results[backend][name]={"median_ms":statistics.median(nums),"samples_ms":nums}
 print(backend,results[backend],flush=True)
(r/"results.json").write_text(json.dumps(results,indent=2))

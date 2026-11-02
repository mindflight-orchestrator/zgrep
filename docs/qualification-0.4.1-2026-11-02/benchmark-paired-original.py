import os,random,statistics as st,subprocess,sys,time,hashlib
S=sys.argv[1];F=sys.argv[2].split(',') if len(sys.argv)>2 else None;N=int(sys.argv[3]) if len(sys.argv)>3 else 40;TS=sys.argv[4:] ;C=S+'/corpus.log';env=dict(os.environ,LC_ALL='C')
cases=[('all plain',['-F','INFO'],0),('forced text',['-a','-F','INFO'],0),('dense plain',['-F','status=200'],0),('numbered',['-n','-F','INFO'],0),('colored',['--color=always','-F','INFO'],0),('sparse',['-F','rare-needle'],0),('regex',['-E','status=500 latency_us=1[0-9]+'],0),('stdin redirected',['-F','INFO'],1),('stdin regex',['-E','stat(u)s=500'],1),('stdin -I',['-I','-F','INFO'],1),('pipe',['-F','INFO'],2),('pipe regex',['-E','stat(u)s=500'],2)]
random.seed(7)
def once(b,a,m):
    out=open(S+'/o.tmp','wb')
    t=time.perf_counter()
    if m==0: p=subprocess.run(TS+[b]+a+[C],stdout=out,env=env)
    elif m==1: p=subprocess.run(TS+[b]+a,stdin=open(C,'rb'),stdout=out,env=env)
    else:
        c=subprocess.Popen(['cat',C],stdout=subprocess.PIPE); p=subprocess.run(TS+[b]+a,stdin=c.stdout,stdout=out,env=env); c.stdout.close(); c.wait()
    return (time.perf_counter()-t)*1e3
def sha():
    return hashlib.sha256(open(S+'/o.tmp','rb').read()).hexdigest()
for tool in ('zgr','zgrc'):
  B=f'{S}/base/bin/{tool}';K=f'{S}/cand/bin/{tool}'
  for name,a,m in cases:
    if F and name not in F:continue
    once(B,a,m);h1=sha();once(K,a,m);h2=sha()
    d=[];bs=[];cs=[]
    for i in range(N):
        o=[(B,bs),(K,cs)];random.shuffle(o)
        for b,l in o:l.append(once(b,a,m))
        d.append(cs[-1]/bs[-1]-1)
    boots=sorted(st.median(random.choices(d,k=len(d))) for _ in range(5000))
    print(f'{tool:5}{name:18} base {st.median(bs):8.2f} cand {st.median(cs):8.2f} diff {st.median(d)*100:+6.2f}% CI[{boots[125]*100:+6.2f},{boots[4875]*100:+6.2f}] bytes_same={h1==h2}',flush=True)

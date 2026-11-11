import os,random,statistics as st,subprocess,sys,time,resource
C=sys.argv[1];A=sys.argv[2];Bs=sys.argv[3:];env=dict(os.environ,LC_ALL='C');args=['-F','status=200',C]
def once(b):
    o=open(os.path.dirname(C)+'/o2.tmp','wb');r0=resource.getrusage(resource.RUSAGE_CHILDREN);t=time.perf_counter();subprocess.run([b]+args,stdout=o,env=env);w=(time.perf_counter()-t)*1e3;r1=resource.getrusage(resource.RUSAGE_CHILDREN);return w,(r1.ru_utime-r0.ru_utime)*1e3,(r1.ru_stime-r0.ru_stime)*1e3
for B in Bs:
    x=[];y=[];random.seed(3)
    for i in range(30):
        o=[(A,x),(B,y)];random.shuffle(o)
        for b,l in o:l.append(once(b))
    m=lambda l,k:st.median(r[k] for r in l)
    d=st.median(y[i][0]/x[i][0]-1 for i in range(30))*100
    print(f'{os.path.basename(os.path.dirname(os.path.dirname(B))):14} wall {m(x,0):7.2f}->{m(y,0):7.2f} ({d:+.1f}%) user {m(x,1):7.1f}->{m(y,1):7.1f} sys {m(x,2):6.1f}->{m(y,2):6.1f}',flush=True)

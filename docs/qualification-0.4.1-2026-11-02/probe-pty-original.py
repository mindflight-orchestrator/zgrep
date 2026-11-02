import os,pty,select,subprocess,sys,time,statistics as st,tty
Z=sys.argv[1];G='/usr/bin/grep';C=sys.argv[2]
env=dict(os.environ,LC_ALL='C')
def run(cmd,stdin_file=None,feed=False):
    m,s=pty.openpty();a=tty.tcgetattr(s);a[1]&=~1;tty.tcsetattr(s,tty.TCSANOW,a)
    t0=time.perf_counter()
    if feed:
        cat=subprocess.Popen(['cat',C],stdout=subprocess.PIPE); si=cat.stdout
    else: si=subprocess.DEVNULL; cat=None
    p=subprocess.Popen(cmd,stdin=si,stdout=s,stderr=subprocess.DEVNULL,env=env)
    os.close(s); first=None;n=0;reads=0
    while True:
        try:d=os.read(m,1<<20)
        except OSError:break
        if not d:break
        if first is None:first=time.perf_counter()-t0
        n+=len(d);reads+=1
    p.wait()
    if cat:cat.stdout.close();cat.wait()
    os.close(m)
    return (time.perf_counter()-t0)*1e3,(first or 0)*1e3,n
def show(n,cmd,feed=False,N=5):
    r=[run(cmd,feed=feed) for _ in range(N)]
    print(f'{n:44} total {st.median(x[0] for x in r):9.1f} ms first {st.median(x[1] for x in r):8.2f} ms bytes {r[0][2]}')
for name,args in [('-F INFO all',['-F','INFO']),('-F rare sparse',['-F','rare-needle']),('regex late',['-E','request_id=[0-9a-f]+ route=/api/item/99999 ']),('-A1 sparse',['-A1','-F','rare-needle'])]:
    show('file '+name+' zgr',[Z]+args+[C]); show('file '+name+' zgr --lb',[Z,'--line-buffered']+args+[C]); show('file '+name+' GNU',[G]+args+[C])
for name,args in [('-F INFO all',['-F','INFO']),('-F rare sparse',['-F','rare-needle'])]:
    show('stdin '+name+' zgr',[Z]+args,feed=True); show('stdin '+name+' zgr --lb',[Z,'--line-buffered']+args,feed=True); show('stdin '+name+' GNU',[G]+args,feed=True)

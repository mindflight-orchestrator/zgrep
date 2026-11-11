import os,pty,select,subprocess,sys,time,signal,tty
Z=sys.argv[1]; G='/usr/bin/grep'
def run(bin,args,chunks,mode,wait=.25):
    env=dict(os.environ,LC_ALL='C'); env.pop('GREP_COLORS',None)
    r,w=os.pipe()
    if mode=='pty':
        m,s=pty.openpty(); a=tty.tcgetattr(s); a[1]&=~1; tty.tcsetattr(s,tty.TCSANOW,a)
    else: m,s=os.pipe()
    p=subprocess.Popen([bin]+args,stdin=r,stdout=s,stderr=subprocess.PIPE,env=env)
    os.close(r);os.close(s)
    os.set_blocking(m,False)
    tl=[]
    def drain(t):
        end=time.time()+t;b=b''
        while time.time()<end:
            x,_,_=select.select([m],[],[],max(0,end-time.time()))
            if x:
                try:
                    d=os.read(m,65536)
                except OSError: break
                if not d:break
                b+=d
        return b
    alive=True
    for c in chunks:
        try: os.write(w,c)
        except BrokenPipeError: tl.append('EPIPE');break
        tl.append(drain(wait))
    ex_before=p.poll()
    try: os.close(w)
    except OSError: pass
    tail=drain(.3)
    try: rc=p.wait(2)
    except subprocess.TimeoutExpired: p.kill();rc='HANG'
    err=p.stderr.read()
    os.close(m)
    return tl,tail,rc,ex_before,err
A=b'needle a\n';Bb=b'needle b\n';X=b'other\n'
cases=[
 ('default',[],[A,Bb]),
 ('regex',['-E','need(le)'],[A,Bb]),
 ('lb',['--line-buffered'],[A,Bb]),
 ('-I lb',['-I','--line-buffered'],[A,Bb]),
 ('-z lb',['-z','--line-buffered'],[b'needle a\0',b'needle b\0']),
 ('-z',['-z'],[b'needle a\0',b'needle b\0']),
 ('-m1',['-m1'],[A,Bb]),
 ('-m1 lb',['-m1','--line-buffered'],[A,Bb]),
 ('-c',['-c'],[A,Bb]),
 ('-l',['-l'],[A,Bb]),
 ('-q',['-q'],[A,Bb]),
 ('-A1',['-A1'],[A,X,X,Bb]),
 ('-A1 lb',['-A1','--line-buffered'],[A,X,X,Bb]),
 ('-B1',['-B1'],[X,A,X]),
 ('-o',['-o'],[A,Bb]),
 ('-n',['-n'],[A,Bb]),
 ('color',['--color=always'],[A,Bb]),
 ('late NUL',[],[A,b'x\0needle\n',Bb]),
 ('late NUL lb',['--line-buffered'],[A,b'x\0needle\n',Bb]),
 ('late NUL -I lb',['-I','--line-buffered'],[A,b'x\0needle\n',Bb]),
 ('first NUL -I lb',['-I','--line-buffered'],[b'x\0\n',A]),
 ('partial',['--line-buffered'],[b'need',b'le a\n']),
]
for mode in ['pty','pipe']:
  print('#####',mode)
  for n,a,c in cases:
    if mode=='pipe' and n not in('default','lb','-I lb','-z lb','-m1','-m1 lb','-A1 lb','late NUL lb','late NUL -I lb'):continue
    for name,b in [('zgr',Z),('gnu',G)]:
        pat=[] if any(x.startswith('-E') for x in a) else ['needle']
        t,tail,rc,ex,err=run(b,a+pat,c,mode)
        print(f'{n:16}{name:4} tl={t} eof={tail!r} rc={rc} exited_early={ex} err={err!r}')

import os,pty,termios,subprocess,select,time,errno,pathlib,json
root=pathlib.Path('/tmp/zgr-plan-review-evidence');results=[]
for label,binary in [('zgr040','/tmp/zgr-plan-review-v040/bin/zgr'),('grep','/usr/bin/grep')]:
    for extra in [[],['--line-buffered']]:
        master,slave=pty.openpty();attrs=termios.tcgetattr(slave);attrs[1]&=~termios.OPOST;termios.tcsetattr(slave,termios.TCSANOW,attrs)
        p=subprocess.Popen([binary,*extra,'-F','needle'],stdin=subprocess.PIPE,stdout=slave,stderr=subprocess.PIPE,env=dict(os.environ,LC_ALL='C'))
        os.close(slave)
        stages=[]
        for line in [b'needle first\n',b'needle second\n']:
            start=time.perf_counter();p.stdin.write(line);p.stdin.flush()
            ready=select.select([master],[],[],0.2)[0]
            data=os.read(master,65536) if ready else b''
            stages.append({'visible_before_next_input_or_eof':bool(data),'received':data.decode(),'elapsed_ms':round((time.perf_counter()-start)*1000,3)})
        p.stdin.close();remaining=b''
        while True:
            try:data=os.read(master,65536)
            except OSError as e:
                if e.errno==errno.EIO:break
                raise
            if not data:break
            remaining+=data
        os.close(master);code=p.wait(timeout=5)
        record={'tool':label,'flags':extra,'stages':stages,'after_eof':remaining.decode(),'exit_status':code}
        results.append(record);print(json.dumps(record),flush=True)
(root/'live-tty-results.json').write_text(json.dumps(results,indent=2)+'\n')

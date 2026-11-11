import pathlib, subprocess, time, os, hashlib, json, statistics, tempfile, random
root=pathlib.Path('/tmp/zgr-plan-review-evidence');root.mkdir(exist_ok=True)
corpus=root/'corpus.log'
subprocess.run(['sh','/tmp/zgr-plan-review-source/bench/generate.sh',str(corpus),'1500000'],check=True)
env=dict(os.environ,LC_ALL='C');rng=random.Random(914)
bins={'zgr040':'/tmp/zgr-plan-review-v040/bin/zgr','zgrc040':'/tmp/zgr-plan-review-v040/bin/zgrc','grep':'/usr/bin/grep'}
cases=[('all plain',['-F','INFO']),('all forced text',['-a','-F','INFO']),('dense plain',['-F','status=200']),('all numbered',['-F','-n','INFO']),('all colored',['--color=always','-F','INFO']),('sparse plain',['-F','rare-needle'])]
result={'baseline_commit':'50f7533649211f87b573826784172e61c71a9830','corpus_bytes':corpus.stat().st_size,'corpus_sha256':hashlib.file_digest(corpus.open('rb'),'sha256').hexdigest(),'locale':'C','runs':7,'cases':[]}
for name,args in cases:
    files={label:root/(label+'.out') for label in bins}
    def run(label):
        with files[label].open('wb') as out,tempfile.TemporaryFile() as err:
            start=time.perf_counter();p=subprocess.Popen([bins[label],*args,str(corpus)],env=env,stdout=out,stderr=err)
            _,status,usage=os.wait4(p.pid,0);elapsed=time.perf_counter()-start;p.returncode=os.waitstatus_to_exitcode(status)
            if p.returncode not in (0,1):err.seek(0);raise RuntimeError((label,name,p.returncode,err.read()))
        return {'wall_ms':elapsed*1000,'user_ms':usage.ru_utime*1000,'sys_ms':usage.ru_stime*1000,'maxrss_kib':usage.ru_maxrss,'status':p.returncode}
    warm={label:run(label) for label in bins}
    digests={label:hashlib.file_digest(files[label].open('rb'),'sha256').hexdigest() for label in bins}
    assert len(set(digests.values()))==1,(name,digests)
    assert len(set(w['status'] for w in warm.values()))==1
    rows={label:[] for label in bins}
    for _ in range(7):
        order=list(bins);rng.shuffle(order)
        for label in order:rows[label].append(run(label))
    summary={label:{metric:round(statistics.median(v[metric] for v in values),3) for metric in ['wall_ms','user_ms','sys_ms','maxrss_kib']} for label,values in rows.items()}
    print(name,json.dumps(summary),flush=True)
    result['cases'].append({'name':name,'args':args,'output_bytes':files['grep'].stat().st_size,'output_sha256':digests['grep'],'correct':True,'summary':summary,'samples':rows})
    (root/'file-results.json').write_text(json.dumps(result,indent=2)+'\n')
for file in root.glob('*.out'):file.unlink()

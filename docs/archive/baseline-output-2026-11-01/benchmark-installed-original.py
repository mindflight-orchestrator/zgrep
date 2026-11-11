import os, pathlib, random, statistics, subprocess, tempfile, time, json
ZGR='/home/dlamotte/.local/bin/zgr'
GEN='/home/dlamotte/Documents/mindflight/zgrep/bench/generate.sh'
env=dict(os.environ, LC_ALL='C')
rng=random.Random(42)
with tempfile.TemporaryDirectory(prefix='installed-zgr-bench-',dir='/tmp') as tmp:
    root=pathlib.Path(tmp); corpus=root/'corpus.log'; tree=root/'tree'; tree.mkdir()
    subprocess.run(['sh',GEN,str(corpus),'1500000'],check=True)
    with corpus.open('rb') as f: chunk=f.read(32768)
    for i in range(1024): (tree/f'{i:04d}.log').write_bytes(chunk)
    cases=[
      ('literal miss',['-F','-c','absent-needle-xyz',str(corpus)]),
      ('rare literal count',['-F','-c','rare-needle',str(corpus)]),
      ('dense literal count',['-F','-c','status=200',str(corpus)]),
      ('case-insensitive count',['-F','-i','-c','info',str(corpus)]),
      ('dense ERE count',['-E','-c','status=(200|500)',str(corpus)]),
      ('inner-literal ERE count',['-E','-c','route=/api/item/[[:digit:]]+[[:space:]]+status=500',str(corpus)]),
      ('no-literal ERE count',['-E','-c','[0-9]{8}',str(corpus)]),
      ('sparse line output',['-F','-n','rare-needle',str(corpus)]),
      ('dense line output',['-F','status=200',str(corpus)]),
      ('recursive rare count',['-r','-F','-c','rare-needle',str(tree)]),
      ('recursive miss',['-r','-F','-c','absent-needle-xyz',str(tree)]),
    ]
    records=[]
    for name,args in cases:
        ref=root/'ref'; out=root/'out'
        def run(binary,path):
            with path.open('wb') as sink:
                start=time.perf_counter()
                p=subprocess.run([binary,*args],env=env,stdout=sink,stderr=subprocess.PIPE)
                elapsed=time.perf_counter()-start
            if p.returncode not in (0,1): raise RuntimeError((name,binary,p.returncode,p.stderr))
            return elapsed,p.returncode
        _,gcode=run('/usr/bin/grep',ref); _,zcode=run(ZGR,out)
        gdata,zdata=ref.read_bytes(),out.read_bytes()
        equal=gcode==zcode and (sorted(gdata.splitlines())==sorted(zdata.splitlines()) if name.startswith('recursive') else gdata==zdata)
        if not equal:
            print(json.dumps({'case':name,'correct':False,'grep_status':gcode,'zgr_status':zcode,'grep_bytes':len(gdata),'zgr_bytes':len(zdata)}),flush=True);continue
        values={'grep':[],'zgr':[]}
        for _ in range(9):
            order=[('grep','/usr/bin/grep'),('zgr',ZGR)];rng.shuffle(order)
            for label,binary in order: values[label].append(run(binary,out)[0]*1000)
        g=statistics.median(values['grep']); z=statistics.median(values['zgr'])
        row={'case':name,'correct':True,'grep_ms':round(g,3),'zgr_ms':round(z,3),'grep_div_zgr':round(g/z,2),'grep_range_ms':[round(min(values['grep']),2),round(max(values['grep']),2)],'zgr_range_ms':[round(min(values['zgr']),2),round(max(values['zgr']),2)]}
        records.append(row);print(json.dumps(row),flush=True)
    pathlib.Path('/tmp/bench-installed-zgr-results.json').write_text(json.dumps({'corpus_bytes':corpus.stat().st_size,'tree_bytes':len(chunk)*1024,'runs':9,'locale':'C','results':records},indent=2))

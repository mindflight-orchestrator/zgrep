import sys,re
d=sys.argv[1];pad=int(sys.argv[2])
p=d+'/src/scanner.zig';s=open(p).read()
for name in ['scanLiteralFast','selectedOutputWorker','findParallelOutputMatch','emitLine','emitDecoratedLine']:
    m=re.search(r'\nfn '+name+r'\((.*?)\n\) (.*?) \{',s,re.S)
    assert m,name
    s=s[:m.start()]+m.group(0).replace(') '+m.group(2)+' {',') align(64) '+m.group(2)+' {')+s[m.end():]
if pad:
    a='''pub fn scanReader(
    reader: *std.Io.Reader,
    allocator: std.mem.Allocator,
    matchers: []const matcher_mod.Matcher,
    path: []const u8,
    options: ScanOptions,
    writer: *std.Io.Writer,
) !Result {
'''
    assert a in s
    s=s.replace(a,a+'    if (options.initial_tab_width == 987654321) asm volatile (".fill %d, 1, 0x90");\n'%pad)
open(p,'w').write(s)

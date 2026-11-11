"""Run qualified baseline/candidate benchmarks sequentially, without build/test overlap."""
from pathlib import Path
import subprocess

s = Path(__file__).resolve().parent
repo = Path('/home/dlamotte/Documents/mindflight/zgrep')
corpus = Path('/tmp/zgrep-backends-20261111-3ahjbzi8/publication/corpus.txt')
base = ['python3', str(s/'compare-output.py'), '--root', str(repo),
        '--baseline', str(s/'baseline/bin/zgr'), '--candidate', str(s/'qualified/bin/zgr'),
        '--corpus', str(corpus), '--repeats', '25']
commands = [
    ('final-auto', base + ['--suite', 'full']),
    ('final-utf8', base + ['--suite', 'output', '--locale', 'C.UTF-8']),
    ('final-text', base + ['--suite', 'output', '--input-mode', 'text']),
    ('final-four-core', base + ['--suite', 'output', '--cpu', '2,4,6,8', '--repeats', '15']),
    ('final-medium', base + ['--suite', 'output', '--cpu', '2,4,6,8', '--repeats', '15',
                            '--corpus', str(s/'medium.txt')]),
    ('final-small', base + ['--suite', 'output', '--cpu', '2,4,6,8', '--repeats', '25', '--corpus', str(s/'small.txt')]),
    ('medium-confirmation', ['python3', str(s/'confirm-medium.py'), *base[2:], '--suite', 'output', '--cpu', '2,4,6,8', '--repeats', '61', '--corpus', str(s/'medium.txt')]),
    ('final-micro', ['python3', str(repo/'bench/internal.py'),
                     '--library', str(s/'qualified/lib/libzgrep-internal-bench.so'),
                     '--baseline-library', str(s/'baseline/lib/libzgrep-internal-bench.so'),
                     '--corpus', str(corpus), '--cpu', '2', '--repeats', '25']),
]
for name, command in commands:
    with (s/(name+'.log')).open('w') as log:
        subprocess.run(command + ['--output', str(s/(name+'.json'))],
                       stdout=log, stderr=subprocess.STDOUT, check=True)
    print(name, 'passed', flush=True)

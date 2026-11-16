#!/usr/bin/env python3
"""Sample an existing BMusic process. Does not launch or quit the app."""
import argparse
import json
import subprocess
import time
from pathlib import Path

parser = argparse.ArgumentParser()
parser.add_argument('--pid', type=int)
parser.add_argument('--seconds', type=int, default=30)
parser.add_argument('--output', type=Path, default=Path('/tmp/bmusic-memory.json'))
args = parser.parse_args()
pid = args.pid or int(subprocess.check_output(['pgrep', '-x', 'BMusic'], text=True).splitlines()[0])
samples = []
for _ in range(max(1, args.seconds)):
    output = subprocess.check_output(['ps', '-p', str(pid), '-o', 'rss=,%cpu='], text=True).split()
    if not output:
        break
    samples.append({'rss_mib': int(output[0]) / 1024, 'cpu_percent': float(output[1])})
    time.sleep(1)
rss = sorted(s['rss_mib'] for s in samples)
report = {'pid': pid, 'sample_count': len(samples), 'metric': 'RSS; excludes compressed memory and is not physical footprint',
          'median_rss_mib': rss[len(rss)//2] if rss else None, 'peak_rss_mib': max(rss, default=0), 'samples': samples}
args.output.write_text(json.dumps(report, indent=2) + '\n')
print(json.dumps({k: v for k, v in report.items() if k != 'samples'}, indent=2))

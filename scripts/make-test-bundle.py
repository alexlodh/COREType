#!/usr/bin/env python3
"""Make an isolated, distinctly named native UI test bundle from a verified build.

Launch the returned path with CUA. The original optimized executable is retained;
a process-replacing launcher supplies --ui-testing and optional fixture/counters.
The installed app, normal profile, imports and source assets are never modified.
"""
import argparse
from pathlib import Path
import plistlib
import re
import shlex
import shutil
import subprocess

p = argparse.ArgumentParser(description=__doc__)
p.add_argument('--source', type=Path, required=True)
p.add_argument('--output', type=Path, required=True)
p.add_argument('--identity', default='org.sasha.coretype.cpu-test')
p.add_argument('--fixture')
p.add_argument('--report', type=Path)
a = p.parse_args()
if not re.fullmatch(r'[A-Za-z0-9-]+(?:\.[A-Za-z0-9-]+)+', a.identity):
    p.error('Identity must be a valid dotted ASCII bundle identifier.')
source = a.source.resolve()
output = a.output.resolve()
temporary_root = Path('/tmp').resolve()
if output.exists() or not output.is_relative_to(temporary_root) or not output.name.endswith('.app'):
    p.error('Output must be a new app bundle under /tmp.')
if output.is_relative_to(source):
    p.error('Output cannot be inside the source bundle.')
info = plistlib.loads((source/'Contents/Info.plist').read_bytes())
if info.get('CFBundleIdentifier') != 'org.sasha.coretype':
    p.error('Source is not a COREType release bundle.')
if a.identity == info['CFBundleIdentifier']:
    p.error('A UI-test bundle must have a distinct bundle identifier.')
subprocess.run(['codesign', '--verify', '--strict', str(source)], check=True)
shutil.copytree(source, output)
args = ['--ui-testing']
if a.fixture: args += ['--fixture', a.fixture]
if a.report: args += ['--performance-report', str(a.report.absolute())]
launcher = output/'Contents/MacOS/CORETypeTestLauncher'
launcher.write_text('#!/bin/sh\nexec "$(dirname "$0")/COREType" ' + ' '.join(map(shlex.quote,args)) + ' "$@"\n')
launcher.chmod(0o755)
info['CFBundleIdentifier'] = a.identity
info['CFBundleName'] = 'COREType CPU Test'
info['CFBundleDisplayName'] = 'COREType CPU Test'
info['CFBundleExecutable'] = launcher.name
(output/'Contents/Info.plist').write_bytes(plistlib.dumps(info))
binary = output/'Contents/MacOS/COREType'
subprocess.run(['codesign', '--remove-signature', str(binary)], check=True)
subprocess.run(['codesign', '--force', '--sign', '-', str(binary)], check=True)
subprocess.run(['codesign', '--force', '--sign', '-', str(output)], check=True)
subprocess.run(['codesign', '--verify', '--strict', str(output)], check=True)
print(output)

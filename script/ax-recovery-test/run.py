#!/usr/bin/env python3
"""Real, read-only macOS AX recovery regression. Requires a trusted debug app bundle."""
import argparse
import json
import os
from pathlib import Path
import plistlib
import shlex
import signal
import subprocess
import tempfile
import time

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('app', type=Path)
parser.add_argument('--stock-cli', default='/opt/homebrew/bin/aerospace')
parser.add_argument('--report', type=Path, required=True)
parser.add_argument('--target-pid', type=int, help='Optional non-frontmost app for successful-empty/rediscovery test')
args = parser.parse_args()
app = args.app.resolve()
metadata = plistlib.loads((app / 'Contents/Info.plist').read_bytes())
if metadata['CFBundleIdentifier'] != 'bobko.aerospace.debug':
    parser.error('Use the separate debug bundle; do not launch a second production server.')
cli = str(app / 'Contents/MacOS/aerospace')
exe = str(app / 'Contents/MacOS/AeroSpaceApp')

def query(command, *params):
    result = subprocess.run([command, *params, '--json'], capture_output=True, text=True, timeout=10)
    if result.returncode:
        raise RuntimeError(result.stderr.strip())
    return json.loads(result.stdout)

def stock_snapshot():
    return {
        'windows': query(args.stock_cli, 'list-windows', '--all', '--format', '%{window-id} %{workspace} %{window-layout}'),
        'workspaces': query(args.stock_cli, 'list-workspaces', '--all', '--format', '%{workspace} %{monitor-name} %{workspace-is-visible} %{workspace-root-container-layout}'),
        'focus': query(args.stock_cli, 'list-windows', '--focused', '--format', '%{window-id}'),
    }

def windows():
    return query(cli, 'list-windows', '--all', '--format', '%{window-id} %{workspace} %{window-layout} %{app-pid}')

def normalized(rows):
    return sorted(rows, key=lambda row: row['window-id'])

baseline = stock_snapshot()
report = {'tests': [], 'scope': 'Read-only diagnostic; Carbon hotkeys blocked; no native window writes.'}
try:
    with tempfile.TemporaryDirectory(prefix='aerospace-ax-test-') as directory:
        folder = Path(directory)
        library = folder / 'faults.dylib'
        subprocess.run(['/usr/bin/clang', '-dynamiclib', '-framework', 'AppKit', '-framework', 'ApplicationServices', '-framework', 'Carbon', str(Path(__file__).with_name('faults.m')), '-o', str(library)], check=True)
        modes = ['stale', 'transient'] + (['empty'] if args.target_pid else [])
        for mode in modes:
            marker = folder / (mode + '-ready')
            fault = folder / (mode + '-fault')
            config = folder / (mode + '.toml')
            startup = 'exec-and-forget ' + shlex.join(['/usr/bin/touch', str(marker)])
            config.write_text('config-version = 2\nstart-at-login = false\non-focused-monitor-changed = []\nafter-startup-command = [' + json.dumps(startup) + ']\n[mode.main.binding]\n')
            env = dict(os.environ, DYLD_INSERT_LIBRARIES=str(library), AEROSPACE_TEST_STALE_AX_FILE=str(fault), AEROSPACE_TEST_AX_MODE=mode)
            if args.target_pid:
                env['AEROSPACE_TEST_AX_TARGET_PID'] = str(args.target_pid)
            result = {'mode': mode}
            with (folder / (mode + '.log')).open('w+') as log:
                process = subprocess.Popen([exe, '--read-only', '--config-path', str(config)], env=env, stdin=subprocess.DEVNULL, stdout=log, stderr=subprocess.STDOUT, start_new_session=True)
                try:
                    deadline = time.monotonic() + 20
                    while not marker.exists():
                        if process.poll() is not None or time.monotonic() > deadline:
                            log.seek(0)
                            raise RuntimeError('Diagnostic failed to start: ' + log.read()[-2000:])
                        time.sleep(.1)
                    before = normalized(windows())
                    if not before:
                        raise RuntimeError('No managed windows at baseline; check AX permission.')
                    fault.touch()
                    samples = []
                    for _ in range(6):
                        time.sleep(.35)
                        samples.append(normalized(windows()))
                    expected = before if mode != 'empty' else [row for row in before if row['app-pid'] != args.target_pid]
                    if mode == 'empty' and len(expected) == len(before):
                        raise RuntimeError('Target PID has no managed windows.')
                    # The first CLI read can precede the heavy refresh scheduled by that read.
                    if any(row != expected for row in samples[-3:]):
                        raise AssertionError(f'{mode}: model did not stabilize at expected windows')
                    fault.unlink()
                    recovered = []
                    for _ in range(6):
                        time.sleep(.35)
                        recovered.append(normalized(windows()))
                    if any(row != before for row in recovered[-3:]):
                        raise AssertionError(f'{mode}: windows or layout did not recover')
                    result.update(passed=True, baseline=before, fault_samples=samples, recovered_samples=recovered)
                finally:
                    if process.poll() is None:
                        process.send_signal(signal.SIGINT)
                        try:
                            process.wait(timeout=8)
                        except subprocess.TimeoutExpired:
                            process.kill()
                            process.wait(timeout=5)
                    report['tests'].append(result)
            if stock_snapshot() != baseline:
                raise AssertionError('Original desktop state changed during diagnostic')
    report['passed'] = True
except Exception as error:
    report.update(passed=False, error=str(error))
finally:
    report['original_unchanged'] = stock_snapshot() == baseline
    args.report.parent.mkdir(parents=True, exist_ok=True)
    args.report.write_text(json.dumps(report, indent=2) + '\n')
print(json.dumps({key: value for key, value in report.items() if key != 'tests'}))
raise SystemExit(0 if report['passed'] and report['original_unchanged'] else 1)

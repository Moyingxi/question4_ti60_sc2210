"""Run a selected V10 portable RTL test in an isolated local build directory."""
from pathlib import Path
import datetime
import hashlib
import json
import re
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[1]
BIN = Path('D:/vivado/Vivado/2023.1/bin')
name = sys.argv[1]
tag = next((x[6:] for x in sys.argv[2:] if x.startswith('--tag=')), '')
assert not tag or re.fullmatch(r'[a-z0-9_]+',tag)
isolated=True
test_args=[x for x in sys.argv[2:] if not x.startswith('--tag=') and x!='--isolated']
stem=name+('_'+tag if tag else '')
run_dir=ROOT/'build'/'sim'/stem
run_dir.mkdir(parents=True,exist_ok=True)
if isolated:
    # A per-test work directory also needs the exact read-only fixture tree.
    # The junction is created only if absent; no fixtures are copied or changed.
    link=run_dir/'sim'
    if not link.exists():
        import os
        if os.name=='nt':
            import _winapi
            _winapi.CreateJunction(str(ROOT/'sim'),str(link))
        else:link.symlink_to(ROOT/'sim',target_is_directory=True)
    assert link.resolve()==(ROOT/'sim').resolve(), 'Unexpected fixture junction target'

assert re.fullmatch(r'tb_[a-z0-9_]+', name), 'invalid test name'
assert name in {s['test'] for s in json.loads((ROOT/'provenance/test_plan.json').read_text(encoding='utf-8'))}, 'test not in V10 plan'
sources = sorted(p for folder in ['rtl/common', 'rtl/control', 'rtl/video', 'rtl/memory']
                 for p in (ROOT / folder).glob('*.v')) + [ROOT / 'sim' / (name + '.sv'),ROOT/'sim/efinix/efx_ram10.v']
if name in ('tb_v8_demo_color','tb_sc2210_lane_order'):
    sources += sorted((ROOT/'sim'/'reference_demo').glob('*.v'))
if name == 'tb_mipi_receiver':
    sources += [ROOT/'vendor/MIPIRx4LaneFre.v']
report = {'test': name, 'simulator': 'XSim 2023.1', 'started': datetime.datetime.now().isoformat(),
          'status': 'RUNNING', 'arguments': sys.argv[2:],
          'execution_directory':str(run_dir),
          'source_sha256': {str(p.relative_to(ROOT)): hashlib.sha256(p.read_bytes()).hexdigest()
                            for p in sources}}
if name=='tb_v8_shapes':
    p=ROOT/'sim/v8_shapes_cases.vh'
    report['source_sha256'][p.relative_to(ROOT).as_posix()]=hashlib.sha256(p.read_bytes()).hexdigest()
for p in (ROOT/'sim').glob('v8_*.hex'):
    if name.startswith('tb_v8_'):
        report['source_sha256'][str(p.relative_to(ROOT))]=hashlib.sha256(p.read_bytes()).hexdigest()
if '-gFULL=1' in test_args:
    for p in (ROOT/'sim'/'full').glob('v8_*.hex'):
        report['source_sha256'][str(p.relative_to(ROOT))]=hashlib.sha256(p.read_bytes()).hexdigest()
json_path = ROOT / 'reports' / (stem + '.xsim.json')
log_path = ROOT / 'reports' / (stem + '.xsim.log')
# A parallel suite may have queued this test before a separately started
# execution finished. Keep that completed execution and its real timestamps
# instead of needlessly running the identical snapshot again.
if json_path.exists() and log_path.exists():
    previous=json.loads(json_path.read_text(encoding='utf-8'))
    if (previous.get('status')=='PASS' and previous.get('arguments')==sys.argv[2:]
            and previous.get('source_sha256')==report['source_sha256']):
        print('REUSE EXACT PASS '+stem+' (existing V10 execution, inputs/arguments unchanged)',flush=True)
        sys.exit(0)
json_path.write_text(json.dumps(report, indent=2), encoding='utf-8')
parameters = []
for arg in test_args:
    assert arg.startswith('-g') and re.fullmatch(r'[A-Za-z0-9_]+=[0-9]+', arg[2:])
    parameters.append('--generic_top "' + arg[2:] + '"')
# Windows供应商.bat逐个转发参数时会拆开未加引号的等号，参数文件绕开该层解析。
if parameters:
    parameter_file = ROOT / 'reports' / (stem + '.xelab.args')
    parameter_file.write_text('\n'.join(parameters) + '\n', encoding='utf-8')
    parameters = ['--file', str(parameter_file)]
commands = [
    [str(BIN / 'xvlog.bat'), '--sv', *map(str, sources)],
    [str(BIN / 'xelab.bat'), name, '-s', name + '_v10', '--mt', '2', *parameters],
    [str(BIN / 'xsim.bat'), name + '_v10', '--runall', '--onerror', 'quit', '--onfinish', 'quit'],
]
all_output = []
passed = False
try:
    for command in commands:
        result = subprocess.run(command, cwd=run_dir, stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                                text=True, encoding='utf-8', errors='replace', timeout=1800)
        all_output.append(result.stdout)
        log_path.write_text('\n'.join(all_output), encoding='utf-8')
        if result.returncode or re.search(r'(?im)^\s*(FATAL(?:_|:|\s)|ERROR(?:_|:|\s))', result.stdout):
            raise RuntimeError(result.stdout[-5000:])
    passed = bool(re.search(r'(?m)^PASS ', all_output[-1]))
    if not passed:
        raise RuntimeError('Simulation did not print PASS\n' + all_output[-1][-4000:])
    print('\n'.join(line for line in all_output[-1].splitlines() if 'PASS ' in line), flush=True)
except Exception as exc:
    print(str(exc), flush=True)
    report['error'] = str(exc)[-6000:]
finally:
    report['status'] = 'PASS' if passed else 'FAIL'
    report['finished'] = datetime.datetime.now().isoformat()
    json_path.write_text(json.dumps(report, indent=2), encoding='utf-8')
sys.exit(0 if passed else 1)

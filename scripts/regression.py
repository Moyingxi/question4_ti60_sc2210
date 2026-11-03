"""Self-contained V10 test ledger, exact dependency verification and optional execution."""
import argparse,concurrent.futures,datetime,json,subprocess,sys
import project
ROOT=project.ROOT
def plan():return json.loads((ROOT/'provenance/test_plan.json').read_text(encoding='utf-8'))
def evidence(s):
    fresh=ROOT/'reports'/(s['name']+'.xsim.json')
    old=s['execution'];r=json.loads(fresh.read_text(encoding='utf-8')) if fresh.exists() else old
    hashes={k.replace('\\','/'):v for k,v in r['source_sha256'].items()}
    changes=[n for n in s['dependencies'] if not (ROOT/n).is_file() or project.sha(ROOT/n)!=hashes.get(n)]
    if [a for a in r.get('arguments',[]) if a!='--isolated']!=s['arguments']:changes.append('arguments')
    return {'name':s['name'],'status':r['status'] if not changes else 'STALE','changes':changes,
        'evidence':'V10_XSIM_EXECUTION' if fresh.exists() else 'FROZEN_EXACT_DEPENDENCIES',
        'original_record_sha256':s['original_record_sha256'],'started':r.get('started'),'finished':r.get('finished'),
        'dependency_count':len(s['dependencies'])}
def execute(s):
    print('START '+s['name'],flush=True)
    project.run('scripts/simulate_xsim.py',s['test'],*s['arguments'],'--isolated')
def main():
    p=argparse.ArgumentParser(description=__doc__);p.add_argument('--run-all',action='store_true');args=p.parse_args()
    tests=plan()
    if args.run_all:
        with concurrent.futures.ThreadPoolExecutor(max_workers=2) as pool:list(pool.map(execute,tests))
    results=[evidence(s) for s in tests]
    r={'project':project.PROJECT,'generated':datetime.datetime.now().isoformat(),'status':'PASS' if all(s['status']=='PASS' for s in results) else 'FAIL',
       'fresh':sum(s['evidence']=='V10_XSIM_EXECUTION' for s in results),'inherited_exact':sum(s['evidence']=='FROZEN_EXACT_DEPENDENCIES' for s in results),'tests':results}
    (ROOT/'reports/regression_v10.json').write_text(json.dumps(r,ensure_ascii=False,indent=2),encoding='utf-8')
    print(json.dumps({k:v for k,v in r.items() if k!='tests'}));return 0 if r['status']=='PASS' else 1
if __name__=='__main__':sys.exit(main())

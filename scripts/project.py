"""V10 local maintenance entry: check, build, tests and validation. No board access."""
from pathlib import Path
import argparse,datetime,hashlib,json,subprocess,sys,xml.etree.ElementTree as ET
ROOT=Path(__file__).resolve().parents[1]
PROJECT='edge_camera_v10'
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def inputs():
    paths=[p for d in ['rtl','vendor','ip','debug'] for p in (ROOT/d).rglob('*') if p.is_file()]
    paths += [ROOT/'scripts'/n for n in ['project.py','vendor.py','write_shape_detector_upgrade_v8.py']]
    paths += [ROOT/(PROJECT+s) for s in ['.xml','.peri.xml','.sdc']]+[ROOT/'cdc.sdc']
    return {p.relative_to(ROOT).as_posix():sha(p) for p in paths}
def run(*args):subprocess.run([sys.executable,'-X','utf8','-B',*map(str,args)],cwd=ROOT,check=True)
def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('action',choices=['check','build','test','validate'])
    args=parser.parse_args()
    if args.action=='check':
        t=ET.parse(ROOT/(PROJECT+'.xml'));ns={'e':'http://www.efinixinc.com/enf_proj'}
        assert t.getroot().get('name')==PROJECT
        assert t.find('.//e:top_module',ns).get('name')==PROJECT+'_top'
        for n in t.findall('.//e:design_file',ns):assert (ROOT/n.get('name')).is_file(),n.get('name')
        print('PASS V10 project identifiers and local source files');return
    if args.action=='test':run('scripts/regression.py','--run-all');return
    if args.action=='validate':run('scripts/validate.py');return
    r={'project':PROJECT,'status':'RUNNING','started':datetime.datetime.now().isoformat(),'source_sha256':inputs()}
    path=ROOT/'reports/build_v10.json'
    path.write_text(json.dumps(r,indent=2),encoding='utf-8')
    try:
        run('scripts/vendor.py','D:/Efinity/scripts/efx_run.py',PROJECT+'.xml','--prj','-f','compile')
        assert inputs()==r['source_sha256'],'Compiler inputs changed during build'
        r.update(status='PASS',bit_sha256=sha(ROOT/'outflow'/ (PROJECT+'.bit')))
    except Exception as exc:r.update(status='FAIL',error=repr(exc));raise
    finally:
        r['finished']=datetime.datetime.now().isoformat();path.write_text(json.dumps(r,indent=2),encoding='utf-8')
if __name__=='__main__':main()

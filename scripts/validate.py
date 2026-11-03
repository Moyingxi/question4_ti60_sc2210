"""Validate V10 using only this directory, installed tools and embedded provenance."""
import ast,datetime,json,re,sys,xml.etree.ElementTree as ET
import project,regression
ROOT=project.ROOT
def read(p):return p.read_text(encoding='utf-8',errors='replace').replace('\0','')
def record(p):return json.loads(read(p))
def main():
    out={'project':project.PROJECT,'generated':datetime.datetime.now().isoformat(),'status':'INCOMPLETE','checks':{},
        'hardware_programmed':False,'hardware_validation':'NOT_REQUESTED_DO_NOT_INHERIT_V9_ACCEPTANCE','scope':'Packaging and unreferenced-file cleanup; active functionality preserved'}
    try:
        b=record(ROOT/'reports/build_v10.json');out['bit_sha256']=project.sha(ROOT/'outflow/edge_camera_v10.bit')
        out['checks']['current_build']=b['status']=='PASS' and b['source_sha256']==project.inputs() and b['bit_sha256']==out['bit_sha256']
        origin=record(ROOT/'provenance/v9_origin.json');changes=[]
        for n,h in origin['retained_source_files_sha256'].items():
            if n.startswith('edge_camera_') or n=='rtl/board/edge_camera_v9_top.v':continue
            if not (ROOT/n).is_file() or project.sha(ROOT/n)!=h:changes.append(n)
        top=read(ROOT/'rtl/board/edge_camera_v10_top.v').replace('edge_camera_v10_top','edge_camera_v9_top').encode('utf-8')
        # Compare exact original bytes as well as universal-newline text.
        raw=(ROOT/'rtl/board/edge_camera_v10_top.v').read_bytes().replace(b'edge_camera_v10_top',b'edge_camera_v9_top')
        import hashlib
        out['checks']['top_only_version_rename']=hashlib.sha256(raw).hexdigest()==origin['retained_source_files_sha256']['rtl/board/edge_camera_v9_top.v']
        out['checks']['io_clock_constraints_identity']=all(
            hashlib.sha256((ROOT/new).read_bytes().replace(b'edge_camera_v10',b'edge_camera_v9')).hexdigest()==origin['retained_source_files_sha256'][old]
            for new,old in [('edge_camera_v10.peri.xml','edge_camera_v9.peri.xml'),('edge_camera_v10.sdc','edge_camera_v9.sdc'),('cdc.sdc','cdc.sdc')])
        out['checks']['retained_rtl_ip_debug_fixture_identity']=not changes;out['source_identity_changes']=changes
        out['tests']=[regression.evidence(s) for s in regression.plan()]
        out['checks']['regressions']=all(t['status']=='PASS' for t in out['tests'])
        out['test_counts']={'executed_v10':sum(t['evidence']=='V10_XSIM_EXECUTION' for t in out['tests']),
                            'inherited_exact_dependencies':sum(t['evidence']=='FROZEN_EXACT_DEPENDENCIES' for t in out['tests'])}
        ns={'e':'http://www.efinixinc.com/enf_proj'};xml=ET.parse(ROOT/'edge_camera_v10.xml')
        out['checks']['local_project']=xml.getroot().get('name')==project.PROJECT and xml.find('.//e:top_module',ns).get('name')==project.PROJECT+'_top' and all((ROOT/n.get('name')).is_file() for n in xml.findall('.//e:design_file',ns))
        out['checks']['unreachable_files_removed']=all(not (ROOT/n).exists() for n in origin['removed_unreachable_rtl'])
        timing=read(ROOT/'outflow/edge_camera_v10.timing.rpt')
        sections=timing.split('Setup (Max) Clock Relationship',1)[1].split('Hold (Min) Clock Relationship',1)
        def rows(s):return [(m[1],m[2],float(m[3])) for m in re.finditer(r'^\s*(\w+)\s+(\w+)\s+[-\d.]+\s+([-\d.]+)\s+\(',s,re.M)]
        setup=rows(sections[0]);hold=rows(sections[1].split('NOTE:',1)[0])
        out['timing']={'setup_min_ns':min(r[2] for r in setup),'hold_min_ns':min(r[2] for r in hold),
                       'pixel_setup_ns':next(r[2] for r in setup if r[:2]==('clk_pixel_2x','clk_pixel_2x'))}
        out['checks']['timing']=min(out['timing'].values())>=0
        csi=timing.split('4. Path Details for Min Critical Paths (begin)',1)[1].split('Path Detail Report (csi_dphy_byte vs csi_rxc_i)',1)[1].split('Path Detail Report (',1)[0]
        u=[float(x) for x in re.findall(r'\+ Clock Uncertainty\s*:\s*([\d.]+)',csi)]
        out['csi_hold_uncertainties_ns']=sorted(set(u));out['checks']['csi_hold_margin']=bool(u) and min(u)>=0.569
        place=read(ROOT/'outflow/edge_camera_v10.place.rpt');out['resources']={}
        for label,key in [('XLRs','XLR'),('Memory Blocks','RAM'),('DSP Blocks','DSP'),('Global Clocks (GBUF)','GBUF')]:
            m=re.search(re.escape(label)+r':\s*(\d+)\s*/\s*(\d+)',place);out['resources'][key]={'used':int(m[1]),'total':int(m[2])}
        out['checks']['resources']=all(v['used']<=v['total'] for v in out['resources'].values())
        tree=ast.parse(read(ROOT/'scripts/write_shape_detector_upgrade_v8.py'))
        rtl=next(n.args[0].value for n in ast.walk(tree) if isinstance(n,ast.Call) and isinstance(n.func,ast.Attribute) and n.func.attr=='write_text' and n.args and isinstance(n.args[0],ast.Constant))
        out['checks']['shape_generator_identity']=rtl==read(ROOT/'rtl/video/v8_shape_detector.v')
        if all(out['checks'].values()):out['status']='PASS'
    except Exception as exc:out['error']=repr(exc)
    (ROOT/'reports/validation_v10.json').write_text(json.dumps(out,ensure_ascii=False,indent=2),encoding='utf-8')
    print(json.dumps({k:v for k,v in out.items() if k!='tests'},ensure_ascii=False,indent=2));return 0 if out['status']=='PASS' else 1
if __name__=='__main__':sys.exit(main())

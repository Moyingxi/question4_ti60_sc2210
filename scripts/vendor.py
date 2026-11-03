"""Run installed Efinity tools with a process-local vendor environment."""
from pathlib import Path
import os, subprocess, sys
EFINITY_ROOT = Path('D:/Efinity')
PROJECT_ROOT = Path(__file__).resolve().parents[1]
def environment():
    env = os.environ.copy()
    for k,v in {'EFINITY_HOME':EFINITY_ROOT,'EFXPT_HOME':EFINITY_ROOT/'pt','EFXPGM_HOME':EFINITY_ROOT/'pgm','EFXDBG_HOME':EFINITY_ROOT/'debugger','EFXIPM_HOME':EFINITY_ROOT/'ipm','EFXSVF_HOME':EFINITY_ROOT/'debugger/svf_player','PYTHONHOME':EFINITY_ROOT/'python311'}.items(): env[k]=str(v)
    env['PATH']=';'.join(str(EFINITY_ROOT/p) for p in ['python311/bin','bin','pgm/bin','debugger/bin','debugger/svf_player/bin','ipm/bin'])+';'+env.get('PATH','')
    env['QT_PLUGIN_PATH']=str(EFINITY_ROOT/'python311')
    env['QT_QPA_PLATFORM_PLUGIN_PATH']=str(EFINITY_ROOT/'python311/platforms')
    env['PYTHONIOENCODING']='utf-8'
    env['PYTHONUTF8']='1'
    tool_state=PROJECT_ROOT/'outflow'/'tool_state'
    tool_state.mkdir(parents=True,exist_ok=True)
    env['EFINITY_USER_DIR_INI']=str(tool_state/'user_dir.ini')
    env['EFINITY_USER_DIR']=str(Path(env['USERPROFILE'])/'.efinity')
    return env
if __name__=='__main__':
    target=sys.argv[1]
    command=[str(EFINITY_ROOT/'python311/bin/python.exe'),'-X','utf8','-B',target,*sys.argv[2:]] if target.endswith('.py') else [target,*sys.argv[2:]]
    sys.exit(subprocess.call(command,env=environment()))

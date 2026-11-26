#!/usr/bin/env python3
"""Run only on a disposable macOS app copy. Relocate Mach-O dylibs recursively."""
import pathlib as P, subprocess as S, sys, shutil, json, os, hashlib, glob, plistlib
app=P.Path(sys.argv[1]).resolve(); c=app/'Contents'; fw=c/'Frameworks'; fw.mkdir(exist_ok=True)
mac=c/'MacOS'; res=c/'Resources'; names=['TLB2Launcher','thelastblade2_boot','thelastblade2_crt']
def run(*a): return S.check_output([str(x) for x in a],text=True)
def deps(p): return [x.strip().split(' (compatibility version',1)[0] for x in run('otool','-L',p).splitlines()[1:] if ' (compatibility version' in x]
def rpaths(p):
 lines=run('otool','-l',p).splitlines(); return [lines[i+2].strip().split(' (offset',1)[0][5:] for i,x in enumerate(lines) if x.strip()=='cmd LC_RPATH' and lines[i+2].strip().startswith('path ')]
def expand(s,origin,exe): return s.replace('@loader_path',str(origin.parent)).replace('@executable_path',str(exe.parent))
def system(s): return s.startswith(('/usr/lib/','/System/Library/'))
seen={}; pending=[]; origins={}; licenses=set()
def add(src):
 src=src.resolve()
 if src in seen:return seen[src]
 if '.framework/' in str(src): raise RuntimeError('Non-system framework requires manual packaging: '+str(src))
 dst=fw/src.name
 if dst.exists() and dst.resolve()!=src:
  if hashlib.sha256(dst.read_bytes()).digest()!=hashlib.sha256(src.read_bytes()).digest(): dst=fw/(hashlib.sha256(str(src).encode()).hexdigest()[:10]+'-'+src.name)
 if not dst.exists(): shutil.copy2(src,dst)
 dst.chmod(0o755); seen[src]=dst; pending.append((src,dst,src)); return dst
for n in names:
 p=mac/n
 if not p.is_file():raise RuntimeError('Missing '+str(p))
 pending.append((p,p,p))
# Find an ICD only when a Vulkan loader is actually linked; allow explicit SDK manifest.
loader=any('libvulkan' in d.lower() for n in names for d in deps(mac/n))
if loader:
 candidates=[]
 if os.getenv('TLB2_ICD_JSON'): candidates=[os.environ['TLB2_ICD_JSON']]
 else:
  sdk=os.getenv('VULKAN_SDK',''); candidates=glob.glob('/opt/homebrew/share/vulkan/icd.d/*Molten*.json')+glob.glob('/opt/homebrew/share/vulkan/icd.d/*molten*.json')+glob.glob(str(P.Path.home()/'VulkanSDK/*/macOS/share/vulkan/icd.d/*Molten*.json'))
  if sdk:candidates+=glob.glob(sdk+'/share/vulkan/icd.d/*Molten*.json')
 if not candidates:
  candidates=glob.glob('/opt/homebrew/etc/vulkan/icd.d/*Molten*.json')+glob.glob('/usr/local/etc/vulkan/icd.d/*Molten*.json')
 if not candidates:raise RuntimeError('MoltenVK ICD not found; set TLB2_ICD_JSON to its JSON path')
 j=P.Path(candidates[0]); data=json.loads(j.read_text()); lib=data['ICD']['library_path']; src=(j.parent/lib).resolve()
 if not src.is_file():
  options=[P.Path('/opt/homebrew/lib')/P.Path(lib).name, P.Path(os.getenv('VULKAN_SDK','/nonexistent'))/'lib'/P.Path(lib).name]; src=next((x for x in options if x.is_file()),src)
 if not src.is_file():raise RuntimeError('ICD library not found: '+lib)
 dst=add(src); data['ICD']['library_path']='../Frameworks/'+dst.name; (res/'MoltenVK_icd.json').write_text(json.dumps(data,indent=2)+'\n')
while pending:
 src,dst,exe=pending.pop(0); print('Inspect',src,flush=True)
 if 'arm64' not in run('lipo','-archs',dst).split():raise RuntimeError('Not ARM64: '+str(dst))
 # Remove existing signatures before rewriting. ad-hoc sign at end.
 S.run(['codesign','--remove-signature',str(dst)],stdout=S.DEVNULL,stderr=S.DEVNULL)
 ids=run('otool','-D',dst).splitlines()[1:]; own=ids[0].strip() if ids else None
 for dep in deps(src):
  if dep==own or system(dep):continue
  if dep.startswith('@rpath/'):
   paths=rpaths(src)+rpaths(mac/'thelastblade2_boot')+rpaths(mac/'thelastblade2_crt')
   opts=[P.Path(expand(x,src,exe))/dep[7:] for x in paths]+[fw/dep[7:],P.Path('/opt/homebrew/lib')/dep[7:]]
  else:opts=[P.Path(expand(dep,src,exe))]
  found=next((x for x in opts if x.is_file()),None)
  if found is None:raise RuntimeError(f'Unresolved {dep} from {src}')
  target=add(found); relative=os.path.relpath(target,dst.parent); S.check_call(['install_name_tool','-change',dep,'@loader_path/'+relative,str(dst)])
 if own:S.check_call(['install_name_tool','-id','@rpath/'+dst.name,str(dst)])
for p in list(seen.values())+[mac/n for n in names]:
 for dep in deps(p):
  if system(dep) or dep=='@rpath/'+p.name:continue
  if not dep.startswith('@loader_path/') or not (p.parent/dep[len('@loader_path/'):]).is_file():raise RuntimeError('Remaining external reference: '+dep)
 if p.name != 'TLB2Launcher':
  S.check_call(['codesign','--force','--sign','-',str(p)])
# Wrapper supplies the relocated ICD to the launcher and its child processes.
wrapper=mac/'StartPortable'; wrapper.write_text('''#!/bin/bash
set -e
HERE="$(cd "$(dirname "$0")" && pwd)"
if [[ -f "$HERE/../Resources/MoltenVK_icd.json" ]]; then
 export VK_DRIVER_FILES="$HERE/../Resources/MoltenVK_icd.json"
 export VK_ICD_FILENAMES="$VK_DRIVER_FILES"
fi
exec "$HERE/TLB2Launcher" "$@"
'''); wrapper.chmod(0o755)
info=c/'Info.plist'; d=plistlib.loads(info.read_bytes()); d['CFBundleExecutable']='StartPortable'; d['CFBundleShortVersionString']='0.28.4'; d['CFBundleVersion']='284'; d['CFBundleIdentifier']=d['CFBundleIdentifier']+'.distribution'; info.write_bytes(plistlib.dumps(d))
S.check_call(['codesign','--force','--sign','-',str(mac/'TLB2Launcher')])
S.check_call(['codesign','--force','--sign','-',str(app)]); S.check_call(['codesign','--verify','--deep','--strict',str(app)])
print('Relocation complete; test on a clean Mac before declaring standalone.')

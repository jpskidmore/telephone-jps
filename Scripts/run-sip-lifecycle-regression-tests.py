#!/usr/bin/env python3
"""Fresh UA source, real WaitingThread, inert native lifecycle C boundaries.

Set JPS_DEBUG_DERIVED_DATA to prebuilt local Debug DerivedData, and optionally
JPS_DEBUG_BUILD_LOG to the successful build output with its clang link command.
Pass a result directory as argument, or results use a fresh local temp folder.
"""
from pathlib import Path
import hashlib, json, os, shlex, subprocess, sys, tempfile
repo=Path(__file__).resolve().parents[1]
output=Path(sys.argv[1]).resolve() if len(sys.argv)>1 else Path(tempfile.mkdtemp(prefix='jps-sip-lifecycle-regressions-'))
output.mkdir(parents=True,exist_ok=True)
derived_data=Path(os.environ.get('JPS_DEBUG_DERIVED_DATA',repo/'build/v3-debug')).resolve()
products=derived_data/'Build/Products/Debug'
derived=derived_data/'Build/Intermediates.noindex/Telephone.build/Debug/Telephone.build/DerivedSources'
if not (derived/'Telephone-Swift.h').exists():
    raise SystemExit('Build local Debug first, then set JPS_DEBUG_DERIVED_DATA to its DerivedData directory.')
sdk=subprocess.check_output(['xcrun','--sdk','macosx','--show-sdk-path'],text=True).strip()
shim_names={'pj_init':'PJInit','pj_shutdown':'PJShutdown','pj_thread_is_registered':'ThreadIsRegistered','pj_thread_register':'ThreadRegister',
 'pjsua_create':'Create','pjsua_pool_create':'PoolCreate','pj_pool_release':'PoolRelease','pjsua_config_default':'ConfigDefault',
 'pjsua_logging_config_default':'LoggingDefault','pjsua_media_config_default':'MediaDefault','pjsua_transport_config_default':'TransportDefault',
 'pjsua_init':'Init','pjmedia_tonegen_create2':'ToneCreate','pjmedia_tonegen_play':'TonePlay','pjsua_conf_add_port':'ConfAdd',
 'pjsua_conf_remove_port':'ConfRemove','pjmedia_port_destroy':'PortDestroy','pjsua_transport_create':'TransportCreate',
 'pjsua_transport_get_info':'TransportInfo','pjsua_enum_codecs':'EnumCodecs','pjsua_codec_set_priority':'SetPriority','pjsua_start':'Start','pjsua_destroy':'Destroy'}
base=['xcrun','clang','-target','arm64-apple-macos15.6','-isysroot',sdk,'-fobjc-arc','-fmodules','-DPJ_AUTOCONF=1',
 '-I'+str(repo/'Telephone'),'-I'+str(repo/'ReceiptValidation'),'-I'+str(repo/'ThirdParty/PJSIP/include'),'-I'+str(derived),'-F'+str(products)]
ua=base+[f'-D{k}=AKProbe{v}' for k,v in shim_names.items()]+['-c',str(repo/'Telephone/AKSIPUserAgent.m'),'-o',str(output/'AKSIPUserAgent.o')]
harness=base+['-c',str(repo/'Tests/SIPLifecycleRegressionHarness.m'),'-o',str(output/'Harness.o')]
subprocess.run(ua,check=True); subprocess.run(harness,check=True)
configured_log=os.environ.get('JPS_DEBUG_BUILD_LOG')
logs=[Path(configured_log)] if configured_log else sorted((repo.parent.parent/'outputs/v3.0').glob('debug-build*.log'),key=lambda p:p.stat().st_mtime)
if not logs or any(not log.exists() for log in logs):
    raise SystemExit('Set JPS_DEBUG_BUILD_LOG to the captured output of a successful local Debug build-for-testing; its application link command is needed.')
commands=[shlex.split(line.strip()) for log in logs for line in log.read_text().splitlines() if ' -dynamiclib ' in line and 'Telephone.debug.dylib' in line and '/usr/bin/clang ' in line]
if not commands:
    raise SystemExit('JPS_DEBUG_BUILD_LOG must contain the local Debug application clang link command, including Telephone.debug.dylib.')
original=commands[-1]
old_filelist=Path(original[original.index('-filelist')+1])
old_derived=str(old_filelist).split('/Build/Intermediates.noindex/')[0]
original=[argument.replace(old_derived,str(derived_data)) for argument in original]
args=[]; i=0
while i<len(original):
    item=original[i]
    if item=='-dynamiclib': i+=1; continue
    if item=='-install_name': i+=2; continue
    if original[i:i+2]==['-Xlinker','-alias']: i+=6; continue
    if item=='-filelist':
        filelist=Path(original[i+1])
        if not filelist.exists():
            raise SystemExit('The chosen local Debug build must retain its application object/link file list. Rebuild with build-for-testing and capture the build log.')
        objects=[p.replace(old_derived,str(derived_data)) for p in filelist.read_text().splitlines()]
        objects=[p for p in objects if Path(p).name not in {'main.o','AKSIPUserAgent.o'}]
        objects += [str(output/'AKSIPUserAgent.o'),str(output/'Harness.o')]
        (output/'objects.txt').write_text('\n'.join(objects)+'\n'); args += [item,str(output/'objects.txt')]; i+=2; continue
    if item=='-o': args += [item,str(output/'SIPLifecycleRegressionHarness')]; i+=2; continue
    if original[i:i+2] in [['-Xlinker','-object_path_lto'],['-Xlinker','-dependency_info']]:
        args+=original[i:i+3]+[str(output/Path(original[i+3]).name)]; i+=4; continue
    args.append(item); i+=1
args+=['-framework','Foundation','-framework','AppKit','-framework','Domain','-framework','UseCases','-Wl,-rpath,'+str(products)]
subprocess.run(args,check=True)
env=dict(os.environ,DYLD_FRAMEWORK_PATH=str(products))
run=subprocess.run([str(output/'SIPLifecycleRegressionHarness')],capture_output=True,text=True,check=True,env=env,timeout=30)
data=json.loads(run.stdout); checks={}
for stage in ['pj-init','thread-register','create','pool','init','tone','conference','transport','start']:
    result=data[stage]
    checks[stage+' failure balances reference']=result['completionReturned'] and result['references']==0 and result['acquired']==result['released'] and not result['ownsReference'] and not result['mediaReady']
    checks[stage+' deferred codec and worker boundary']=result['codecDeferredBeforeStart'] and result['earlySDK']==0 and result['mainSDK']==0
    checks[stage+' tone cleanup']=result['toneCreated']==result['toneDestroyed']
success=data['successfulStartup']; stopped=success['afterStop']; repeated=data['repeatedCycles']['native']
checks['pending startup codec applied']=success['started'] and success['drained'] and success['pendingCodecApplied']
checks['stop asynchronous and FIFO cleanup']=success['stopReturnedAsynchronously'] and success['stopped'] and success['cleanupExecuted'] and success['ordinaryCancelled']
checks['successful shutdown balances']=stopped['references']==0 and stopped['acquired']==stopped['released']==1 and stopped['toneCreated']==stopped['toneDestroyed'] and stopped['earlySDK']==stopped['mainSDK']==0
checks['retired recording finalizes before native teardown']=stopped['recorderStops']==1 and stopped['unsafeRecorderStops']==0 and stopped['endpointDestroyedWithRecorder']==0
checks['repeated startup teardown balances']=data['repeatedCycles']['completed'] and repeated['references']==0 and repeated['acquired']==repeated['released']==4 and repeated['earlySDK']==repeated['mainSDK']==0
(output/'results.json').write_text(json.dumps({'checks':checks,'data':data,'stderr':run.stderr},indent=2)+'\n')
(output/'provenance.json').write_text(json.dumps({'sourceSHA256':hashlib.sha256((repo/'Telephone/AKSIPUserAgent.m').read_bytes()).hexdigest(),
 'compile':ua,'link':args,'nativeShims':shim_names,'boundary':'Fresh production UA methods, real WaitingThread and async main completion. No application/profile/Keychain/Contacts/audio initializer or actual SIP/PJLIB/native endpoint.'},indent=2)+'\n')
assert all(checks.values()),{key:passed for key,passed in checks.items() if not passed}
print(json.dumps({'passed':len(checks),'issues':[14,17,47,50,51],'resultsDirectory':str(output)},indent=2))

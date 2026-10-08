#!/usr/bin/env python3
"""Compile current callbacks with inert boundaries; never start SIP.

JPS_DEBUG_DERIVED_DATA selects a prebuilt local Debug DerivedData directory.
Pass a result directory as argument, or results use a fresh local temp folder.
"""
from pathlib import Path
import hashlib, json, os, subprocess, sys, tempfile
repo = Path(__file__).resolve().parents[1]
derived_data = Path(os.environ.get('JPS_DEBUG_DERIVED_DATA', repo / 'build/v3-debug')).resolve()
products = derived_data / 'Build/Products/Debug'
if not (products/'UseCases.framework').exists():
    raise SystemExit('Build local Debug first, then set JPS_DEBUG_DERIVED_DATA to its DerivedData directory.')
output = Path(sys.argv[1]).resolve() if len(sys.argv)>1 else Path(tempfile.mkdtemp(prefix='jps-sip-callback-regressions-'))
output.mkdir(parents=True, exist_ok=True)
sdk = subprocess.check_output(['xcrun','--sdk','macosx','--show-sdk-path'],text=True).strip()
sources = ['PJSUAOnIncomingCall.m','PJSUAOnCallReplaced.m','PJSUAOnCallState.m','PJSUAOnCallTransferStatus.m','PJSUACallInfo.m','AKNSString+PJSUA.m','AKSIPCallNotifications.m']
args = ['xcrun','clang','-target','arm64-apple-macos15.6','-isysroot',sdk,'-fobjc-arc','-fmodules','-DPJ_AUTOCONF=1','-I'+str(repo/'Telephone'),'-I'+str(repo/'ThirdParty/PJSIP/include'),'-F'+str(products),str(repo/'Tests/SIPCallbackRegressionHarness.m'),*[str(repo/'Telephone'/name) for name in sources],'-L'+str(repo/'ThirdParty/PJSIP/lib'),'-lpj-arm-apple-darwin','-framework','Foundation','-framework','UseCases','-Wl,-rpath,'+str(products),'-o',str(output/'SIPCallbackRegressionHarness')]
subprocess.run(args,check=True)
run = subprocess.run([str(output/'SIPCallbackRegressionHarness')],capture_output=True,text=True,check=True,timeout=15)
data=json.loads(run.stdout)
checks = {
 'ordinary incoming owner':data['ordinaryIncoming']['delegateCount']==1 and data['ordinaryIncoming']['modelCount']==1,
 'replacement controller handoff':data['replacementIncoming']['replacementCount']==1,
 'replacement confirmation':data['replacementIncoming']['events'][0]['call']==2,
 'final transfer same source':data['successfulTransfer']['sourceFilteredNotificationCount']==1 and data['successfulTransfer']['sourceTransferStatus']==200,
 'transfer published before disconnect':data['successfulTransfer']['events'][0]['name']=='AKSIPCallTransferStatusDidChange',
 'hangup once':data['successfulTransfer']['hangups']==1 and data['successfulTransfer']['modelCount']==0,
 'final notification stops':not data['successfulTransfer']['wantsMore'],
 'removed incoming no nil notification':data['accountRemovedBeforeQueuedIncoming']['delegateCount']==0 and data['accountRemovedBeforeQueuedIncoming']['events']==[],
 'reused account slot':data['reusedAccountSlotRejectsOldIncoming']=={'oldDelegate':0,'newDelegate':0,'newModels':0},
 'provisional stays connected':data['provisionalTransfer']['hangups']==0 and data['provisionalTransfer']['wantsMore'],
 'failure stays connected':data['failedTransfer']['hangups']==0 and data['failedTransfer']['status']==486,
}
(output/'results.json').write_text(json.dumps({'checks':checks,'data':data,'stderr':run.stderr},indent=2)+'\n')
(output/'provenance.json').write_text(json.dumps({'sources':{name:hashlib.sha256((repo/'Telephone'/name).read_bytes()).hexdigest() for name in sources},'command':args,'boundary':'Current production callbacks, inert native get_info/hangup/dump and inert models. No SIP endpoint, application startup, accounts, profile, audio or provider.'},indent=2)+'\n')
assert all(checks.values()), checks
print(json.dumps({'passed':len(checks),'issues':[21,22,23],'noNativeSIP':True,'resultsDirectory':str(output)},indent=2))

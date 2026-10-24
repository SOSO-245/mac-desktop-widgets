#!/usr/bin/env python3
"""Build embedded WidgetKit extension with Xcode's AppIntents metadata extraction."""
from pathlib import Path
import sys, tempfile, plistlib, subprocess, hashlib, datetime
root=Path(__file__).resolve().parents[1]
app=Path(sys.argv[1]); stage=Path(tempfile.mkdtemp(prefix='nikki-widget-'))
project=stage/'NikkiWidget.xcodeproj';project.mkdir()
objects={}
def put(keyname,**value):
 key=hashlib.sha256(keyname.encode()).hexdigest()[:24].upper();objects[key]=value;return key
sources=[root/'Sources/Model.swift',root/'Sources/WidgetData.swift',root/'Widget/Widget.swift']
refs=[];builds=[]
for p in sources:
 ref=put(p.name,isa='PBXFileReference',lastKnownFileType='sourcecode.swift',path=str(p),sourceTree='<absolute>');refs.append(ref)
 builds.append(put('build'+p.name,isa='PBXBuildFile',fileRef=ref))
resources=[]
for name,kind in [('SiteIcons','folder'),('AppIcon.icns','image.icns')]:
 ref=put(name,isa='PBXFileReference',lastKnownFileType=kind,path=str(root/'Assets'/name),sourceTree='<absolute>');refs.append(ref)
 resources.append(put('build'+name,isa='PBXBuildFile',fileRef=ref))
product=put('product',isa='PBXFileReference',explicitFileType='wrapper.app-extension',path='NikkiWidget.appex',sourceTree='BUILT_PRODUCTS_DIR')
group=put('group',isa='PBXGroup',children=refs+[product],sourceTree='<group>')
sourcephase=put('sources',isa='PBXSourcesBuildPhase',buildActionMask=2147483647,files=builds,runOnlyForDeploymentPostprocessing=0)
resphase=put('resources',isa='PBXResourcesBuildPhase',buildActionMask=2147483647,files=resources,runOnlyForDeploymentPostprocessing=0)
info=dict(CFBundleExecutable='$(EXECUTABLE_NAME)',CFBundleIdentifier='$(PRODUCT_BUNDLE_IDENTIFIER)',CFBundleName='NikkiWidget',CFBundleDisplayName='Nikki 实时卡片',CFBundleIconFile='AppIcon',CFBundlePackageType='XPC!',CFBundleShortVersionString='1.1.0',CFBundleVersion=datetime.datetime.now().strftime('%Y%m%d%H%M%S'),LSMinimumSystemVersion='14.0',NSExtension={'NSExtensionPointIdentifier':'com.apple.widgetkit-extension'},NSAppTransportSecurity={'NSAllowsLocalNetworking':True})
info['CFBundleVersion']=plistlib.loads((app/'Contents/Info.plist').read_bytes())['CFBundleVersion']
(stage/'Info.plist').write_bytes(plistlib.dumps(info));(stage/'widget.entitlements').write_bytes(plistlib.dumps({'com.apple.security.app-sandbox':True,'com.apple.security.network.client':True}))
settings=dict(PRODUCT_NAME='NikkiWidget',PRODUCT_BUNDLE_IDENTIFIER='local.homeatlas.NikkiMonitor.Widget',INFOPLIST_FILE=str(stage/'Info.plist'),CODE_SIGN_ENTITLEMENTS=str(stage/'widget.entitlements'),CODE_SIGN_IDENTITY='-',CODE_SIGN_STYLE='Manual',SDKROOT='macosx',MACOSX_DEPLOYMENT_TARGET='14.0',SWIFT_VERSION='5.0',ARCHS='arm64 x86_64',APPLICATION_EXTENSION_API_ONLY='YES',SKIP_INSTALL='YES',GENERATE_INFOPLIST_FILE='NO',LD_RUNPATH_SEARCH_PATHS='$(inherited) @executable_path/../Frameworks @executable_path/../../../../Frameworks')
config=put('config',isa='XCBuildConfiguration',buildSettings=settings,name='Release')
configs=put('configs',isa='XCConfigurationList',buildConfigurations=[config],defaultConfigurationIsVisible=0,defaultConfigurationName='Release')
target=put('target',isa='PBXNativeTarget',name='NikkiWidget',productName='NikkiWidget',productType='com.apple.product-type.app-extension',productReference=product,buildConfigurationList=configs,buildPhases=[sourcephase,resphase],buildRules=[],dependencies=[])
proj=put('project',isa='PBXProject',buildConfigurationList=configs,compatibilityVersion='Xcode 14.0',developmentRegion='zh_CN',hasScannedForEncodings=0,knownRegions=['zh_CN','en'],mainGroup=group,projectDirPath='',projectRoot='',targets=[target])
(project/'project.pbxproj').write_bytes(plistlib.dumps(dict(archiveVersion='1',classes={},objectVersion='56',objects=objects,rootObject=proj)))
subprocess.run(['xcodebuild','-project',str(project),'-target','NikkiWidget','-configuration','Release','SYMROOT='+str(stage/'build'),'-quiet'],check=True)
destination=app/'Contents/PlugIns/NikkiWidget.appex';destination.parent.mkdir(exist_ok=True)
subprocess.run(['ditto','--norsrc',str(stage/'build/Release/NikkiWidget.appex'),str(destination)],check=True)

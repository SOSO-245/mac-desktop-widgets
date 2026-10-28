#!/usr/bin/env python3
"""Build and package the Mac app. Installation is an explicit --install step."""
import argparse, datetime, hashlib, json, pathlib, plistlib, subprocess, sys, tempfile

import updater_build

ROOT = pathlib.Path(__file__).resolve().parent
PROJECT = ROOT / 'HomeAtlas.xcodeproj'
VERSION = '2.4.3'
APP_NAME = '家庭概览'
APP_FILES = ['ToolboxShared.swift', 'ToolboxBridge.swift', 'AppSettings.swift', 'LiveDesktopCard.swift', 'AppUpdater.swift', 'StatusPopover.swift', 'WidgetSelfRepair.swift', 'MenuCustomization.swift', 'Model.swift', 'EnergyCard.swift', 'PowerWater.swift', 'Host.swift', 'Garage.swift',
             'DashboardData.swift', 'DashboardView.swift', 'ClimateHistory.swift',
             'OverviewService.swift', 'OverviewWindowView.swift']
WIDGET_FILES = ['Model.swift', 'EnergyCard.swift', 'PowerWater.swift', 'Widget.swift']
ALL_FILES = list(dict.fromkeys(APP_FILES + WIDGET_FILES))

def ident(name): return hashlib.sha256(name.encode()).hexdigest()[:24].upper()
objects = {}
def obj(name, value):
    key = ident(name); objects[key] = value; return key
def ref(name): return ident(name)
def q(s): return '"' + str(s).replace('\\', '\\\\').replace('"', '\\"') + '"'
def arr(items): return '(' + ', '.join(items) + ')'
def d(values): return '{ ' + ' '.join(k + ' = ' + v + ';' for k,v in values.items()) + ' }'

def unregister_build_product(app):
    """Keep a temporary build from receiving the installed app's URLs/widgets."""
    lsregister = '/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister'
    subprocess.run([lsregister, '-u', str(app)], check=False,
                   stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    subprocess.run(['pluginkit', '-r', str(app / 'Contents/PlugIns/HomeEnergyWidget.appex')],
                   check=False, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)

def generate_project():
    PROJECT.mkdir(exist_ok=True)
    for name in ALL_FILES:
        obj(name, d({'isa':'PBXFileReference','lastKnownFileType':'sourcecode.swift','path':q('Sources/' + name),'sourceTree':q('<group>')}))
    obj('app-product',d({'isa':'PBXFileReference','explicitFileType':'wrapper.application','path':q(APP_NAME + '.app'),'sourceTree':'BUILT_PRODUCTS_DIR'}))
    obj('widget-product',d({'isa':'PBXFileReference','explicitFileType':'wrapper.app-extension','path':q('HomeEnergyWidget.appex'),'sourceTree':'BUILT_PRODUCTS_DIR'}))
    obj('products',d({'isa':'PBXGroup','children':arr([ref('app-product'),ref('widget-product')]),'name':'Products','sourceTree':q('<group>')}))
    obj('main-group',d({'isa':'PBXGroup','children':arr([ref(n) for n in ALL_FILES + ['icon-file', 'charging-file', 'ribbons-file', 'duck-file', 'products'] + ['duck-'+s+'-file' for s in ['spring','summer','winter','rain','snow','skeleton','cursor','swan','birthday','swan-birthday','rain-wet','basketball','football','swan-spring','swan-summer','swan-winter','swan-rain','swan-snow','swan-skeleton']]]),'sourceTree':q('<group>')}))
    obj('icon-file',d({'isa':'PBXFileReference','lastKnownFileType':'folder.assetcatalog','path':q('Assets/Assets.xcassets'),'sourceTree':q('<group>')}))
    obj('icon-build',d({'isa':'PBXBuildFile','fileRef':ref('icon-file')}))
    obj('widget-icon-build',d({'isa':'PBXBuildFile','fileRef':ref('icon-file')}))
    obj('duck-file',d({'isa':'PBXFileReference','lastKnownFileType':'image.png','path':q('Resources/duck-ai.png'),'sourceTree':q('<group>')}))
    obj('duck-build',d({'isa':'PBXBuildFile','fileRef':ref('duck-file')}))
    obj('widget-duck-build',d({'isa':'PBXBuildFile','fileRef':ref('duck-file')}))
    for season in ['spring','summer','winter','rain','snow','skeleton','cursor','swan','birthday','swan-birthday','rain-wet','basketball','football','swan-spring','swan-summer','swan-winter','swan-rain','swan-snow','swan-skeleton']:
        key='duck-'+season
        obj(key+'-file',d({'isa':'PBXFileReference','lastKnownFileType':'image.png','path':q('Resources/'+key+'.png'),'sourceTree':q('<group>')}))
        obj(key+'-build',d({'isa':'PBXBuildFile','fileRef':ref(key+'-file')}))
        obj('widget-'+key+'-build',d({'isa':'PBXBuildFile','fileRef':ref(key+'-file')}))
    obj('widget-resources',d({'isa':'PBXResourcesBuildPhase','buildActionMask':'2147483647','files':arr([ref('widget-icon-build'),ref('widget-duck-build')] + [ref('widget-duck-'+s+'-build') for s in ['spring','summer','winter','rain','snow','skeleton','cursor','swan','birthday','swan-birthday','rain-wet','basketball','football','swan-spring','swan-summer','swan-winter','swan-rain','swan-snow','swan-skeleton']]),'runOnlyForDeploymentPostprocessing':'0'}))
    obj('charging-file',d({'isa':'PBXFileReference','lastKnownFileType':'sourcecode.javascript','path':q('Resources/charging-model.js'),'sourceTree':q('<group>')}))
    obj('charging-build',d({'isa':'PBXBuildFile','fileRef':ref('charging-file')}))
    obj('ribbons-file',d({'isa':'PBXFileReference','lastKnownFileType':'image.png','path':q('Resources/glass-ribbons.png'),'sourceTree':q('<group>')}))
    obj('ribbons-build',d({'isa':'PBXBuildFile','fileRef':ref('ribbons-file')}))
    obj('app-resources',d({'isa':'PBXResourcesBuildPhase','buildActionMask':'2147483647','files':arr([ref('icon-build'),ref('charging-build'),ref('ribbons-build'),ref('duck-build')] + [ref('duck-'+s+'-build') for s in ['spring','summer','winter','rain','snow','skeleton','cursor','swan','birthday','swan-birthday','rain-wet','basketball','football','swan-spring','swan-summer','swan-winter','swan-rain','swan-snow','swan-skeleton']]),'runOnlyForDeploymentPostprocessing':'0'}))
    
    for target, files in [('app',APP_FILES),('widget',WIDGET_FILES)]:
        builds = []
        for f in files:
            name = target + '-' + f
            builds.append(obj(name,d({'isa':'PBXBuildFile','fileRef':ref(f)})))
        obj(target+'-sources',d({'isa':'PBXSourcesBuildPhase','buildActionMask':'2147483647','files':arr(builds),'runOnlyForDeploymentPostprocessing':'0'}))
        obj(target+'-frameworks',d({'isa':'PBXFrameworksBuildPhase','buildActionMask':'2147483647','files':'()','runOnlyForDeploymentPostprocessing':'0'}))
        settings = {'PRODUCT_NAME':q(APP_NAME if target == 'app' else 'HomeEnergyWidget'),
                    'PRODUCT_BUNDLE_IDENTIFIER':q('local.homeatlas.HomeEnergy' + ('.Widget' if target == 'widget' else '')),
                    'INFOPLIST_FILE':q(target + '-Info.plist'),'CODE_SIGN_STYLE':'Manual','CODE_SIGN_IDENTITY':q('-'),
                    'CODE_SIGNING_ALLOWED':'YES','ENABLE_APP_SANDBOX':'YES' if target == 'widget' else 'NO',
                    'CODE_SIGN_ENTITLEMENTS':q(target + '.entitlements'),
                    'LD_RUNPATH_SEARCH_PATHS':q('$(inherited) @executable_path/../Frameworks' + (' @executable_path/../../../../Frameworks' if target == 'widget' else '')),
                    'ASSETCATALOG_COMPILER_APPICON_NAME':'AppIcon','SWIFT_VERSION':'5.0','MACOSX_DEPLOYMENT_TARGET':'14.0','SDKROOT':'macosx',
                    'GENERATE_INFOPLIST_FILE':'NO','ENABLE_HARDENED_RUNTIME':'NO',
                    'SWIFT_EMIT_LOC_STRINGS':'YES','ALWAYS_SEARCH_USER_PATHS':'NO','SKIP_INSTALL':'YES' if target == 'widget' else 'NO'}
        if target == 'app': settings.update(updater_build.xcode_settings(ROOT, q))
        if target == 'widget': settings['APPLICATION_EXTENSION_API_ONLY'] = 'YES'
        configs = [obj(target+'-'+c,d({'isa':'XCBuildConfiguration','buildSettings':d(settings),'name':c})) for c in ['Debug','Release']]
        obj(target+'-configs',d({'isa':'XCConfigurationList','buildConfigurations':arr(configs),'defaultConfigurationIsVisible':'0','defaultConfigurationName':'Release'}))
    
    obj('embed-build',d({'isa':'PBXBuildFile','fileRef':ref('widget-product'),'settings':d({'ATTRIBUTES':arr(['RemoveHeadersOnCopy'])})}))
    obj('embed',d({'isa':'PBXCopyFilesBuildPhase','buildActionMask':'2147483647','dstPath':q(''),'dstSubfolderSpec':'13','files':arr([ref('embed-build')]),'name':q('Embed App Extensions'),'runOnlyForDeploymentPostprocessing':'0'}))
    obj('proxy',d({'isa':'PBXContainerItemProxy','containerPortal':ref('project'),'proxyType':'1','remoteGlobalIDString':ref('widget-target'),'remoteInfo':'HomeEnergyWidget'}))
    obj('dependency',d({'isa':'PBXTargetDependency','target':ref('widget-target'),'targetProxy':ref('proxy')}))
    for t in ['app','widget']:
        phases = [ref(t+'-sources'),ref(t+'-frameworks')] + ([ref('app-resources'),ref('embed')] if t == 'app' else [ref('widget-resources')])
        obj(t+'-target',d({'isa':'PBXNativeTarget','buildConfigurationList':ref(t+'-configs'),'buildPhases':arr(phases),'buildRules':'()',
                         'dependencies':arr([ref('dependency')] if t == 'app' else []),'name':'HomeAtlas' if t == 'app' else 'HomeEnergyWidget',
                         'productName':'HomeAtlas' if t == 'app' else 'HomeEnergyWidget','productReference':ref(t+'-product'),
                         'productType':q('com.apple.product-type.application' if t == 'app' else 'com.apple.product-type.app-extension')}))
    configs = [obj('project-'+c,d({'isa':'XCBuildConfiguration','buildSettings':d({'SWIFT_VERSION':'5.0','MACOSX_DEPLOYMENT_TARGET':'14.0','SDKROOT':'macosx','ARCHS':'arm64'}),'name':c})) for c in ['Debug','Release']]
    obj('project-configs',d({'isa':'XCConfigurationList','buildConfigurations':arr(configs),'defaultConfigurationIsVisible':'0','defaultConfigurationName':'Release'}))
    obj('project',d({'isa':'PBXProject','attributes':d({'LastUpgradeCheck':'2600'}),'buildConfigurationList':ref('project-configs'),'compatibilityVersion':q('Xcode 14.0'),'developmentRegion':'zh-Hans','hasScannedForEncodings':'0','knownRegions':arr(['en',q('zh-Hans')]),'mainGroup':ref('main-group'),'productRefGroup':ref('products'),'projectDirPath':q(''),'projectRoot':q(''),'targets':arr([ref('app-target'),ref('widget-target')])}))
    (PROJECT / 'project.pbxproj').write_text('// !$*UTF8*$!\n' + d({'archiveVersion':'1','classes':'{}','objectVersion':'56','objects':d(objects),'rootObject':ref('project')}))
    
    version = datetime.datetime.now().strftime('%Y%m%d%H%M%S')
    common = {'CFBundleDevelopmentRegion':'zh_CN','CFBundleShortVersionString':VERSION,'CFBundleVersion':version,
              'CFBundleExecutable':'$(EXECUTABLE_NAME)','CFBundleIdentifier':'$(PRODUCT_BUNDLE_IDENTIFIER)',
              'CFBundleName':APP_NAME,'CFBundleIconName':'AppIcon','CFBundleIconFile':'AppIcon','LSMinimumSystemVersion':'14.0',
              'NSAppTransportSecurity':{'NSAllowsArbitraryLoads':True,'NSAllowsLocalNetworking':True}}
    app = dict(common,CFBundlePackageType='APPL',CFBundleDisplayName=APP_NAME,LSUIElement=True,NSPrincipalClass='NSApplication',
               CFBundleURLTypes=[{'CFBundleURLName':'HomeAtlas','CFBundleURLSchemes':['homeenergy','homeatlas']}],
               NSLocalNetworkUsageDescription='只读访问你配置的 Home Assistant，用于显示家庭概览与桌面小组件。')
    widget = dict(common,CFBundlePackageType='XPC!',CFBundleDisplayName=APP_NAME,NSExtension={'NSExtensionPointIdentifier':'com.apple.widgetkit-extension'})
    for n, value in [('app-Info.plist',app),('widget-Info.plist',widget),('app.entitlements',{}),('widget.entitlements',{'com.apple.security.app-sandbox':True,'com.apple.security.network.client':True})]:
        (ROOT/n).write_bytes(plistlib.dumps(value))
    

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--generate-only', action='store_true', help='Write only the Xcode project and its metadata.')
    parser.add_argument('--install', action='store_true', help='Reserved: install the resulting application manually.')
    parser.add_argument('--no-launch', action='store_true', help='With --install, do not launch the new app after installation.')
    args = parser.parse_args()
    if args.generate_only and args.install:
        parser.error('--generate-only cannot be combined with --install')
    required = [ROOT / 'Sources' / name for name in ALL_FILES]
    required += [ROOT / 'Assets/AppIcon.icns', ROOT / 'Resources/charging-model.js', ROOT / 'Resources/glass-ribbons.png', ROOT / 'Resources/duck-ai.png'] + [ROOT / ('Resources/duck-'+s+'.png') for s in ['spring','summer','winter','rain','snow','skeleton','cursor','swan','birthday','swan-birthday','rain-wet','basketball','football','swan-spring','swan-summer','swan-winter','swan-rain','swan-snow','swan-skeleton']]
    missing = [str(path.relative_to(ROOT)) for path in required if not path.is_file()]
    if missing:
        raise SystemExit('Missing required files: ' + ', '.join(missing))
    generate_project()
    if args.generate_only:
        print('Generated:', PROJECT)
        return
    build = pathlib.Path(tempfile.mkdtemp(prefix='homeatlas-mac-build-'))
    subprocess.run(['xcodebuild', '-project', str(PROJECT), '-target', 'HomeAtlas',
                    '-configuration', 'Release', 'SYMROOT=' + str(build),
                    'CODE_SIGN_IDENTITY=-', '-quiet'], cwd=ROOT, check=True)
    app = build / 'Release' / (APP_NAME + '.app')
    updater_build.finish(ROOT, app)
    subprocess.run(['codesign', '--verify', '--deep', '--strict', str(app)], check=True)
    delivery = ROOT / '交付'
    delivery.mkdir(exist_ok=True)
    package = delivery / '家庭概览-Mac.zip'
    temporary = delivery / '.家庭概览-Mac.pending.zip'
    subprocess.run(['ditto', '-c', '-k', '--norsrc', '--keepParent', str(app), str(temporary)], check=True)
    subprocess.run(['unzip', '-tqq', str(temporary)], check=True)
    digest = hashlib.sha256(temporary.read_bytes()).hexdigest()
    temporary.replace(package)
    checksum = package.with_suffix('.zip.sha256')
    checksum.write_text(digest + '  ' + package.name + '\n')
    products = {'version': VERSION, 'project': str(PROJECT), 'app': str(app),
                'widget': str(app / 'Contents/PlugIns/HomeEnergyWidget.appex'),
                'package': str(package), 'sha256': digest, 'checksum': str(checksum)}
    (ROOT / 'build-products.json').write_text(json.dumps(products, ensure_ascii=False, indent=2) + '\n')
    # xcodebuild can register the product even when no installation was requested.
    # Unregister only this run's temporary output, never ~/Applications copies.
    unregister_build_product(app)
    print('Built:', app)
    print('Packaged:', package)
    print('Nothing installed. Install the ZIP manually when ready.')
    if args.install:
        print("Install the generated ZIP manually; existing configuration is preserved.")

if __name__ == '__main__':
    main()

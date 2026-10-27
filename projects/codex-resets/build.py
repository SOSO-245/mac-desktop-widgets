#!/usr/bin/env python3
"""Build the standalone macOS app and WidgetKit extension without dependencies.

By default this only builds and packages the app. Pass --install explicitly to
copy and register the result in ~/Applications. It never stops other apps.
"""
import argparse
import datetime
import hashlib
import json
import pathlib
import plistlib
import subprocess
import tempfile

import updater_build

ROOT = pathlib.Path(__file__).resolve().parent
PROJECT = ROOT / 'CodexResets.xcodeproj'
APP_NAME = 'Codex 重置'
APP_TARGET = 'CodexResets'
WIDGET_NAME = 'CodexResetsWidget'
BUNDLE_ID = 'local.homeatlas.CodexResets'


def run(arguments, **kwargs):
    return subprocess.run([str(argument) for argument in arguments], check=True, **kwargs)


def generate_project():
    PROJECT.mkdir(exist_ok=True)
    objects = {}

    def ident(name):
        return hashlib.sha256(name.encode()).hexdigest()[:24].upper()

    def obj(name, value):
        key = ident(name)
        objects[key] = value
        return key

    def q(value):
        return '"' + str(value).replace('\\', '\\\\').replace('"', '\\"') + '"'

    def arr(values):
        return '(' + ', '.join(values) + ')'

    def d(values):
        return '{ ' + ' '.join(key + ' = ' + value + ';' for key, value in values.items()) + ' }'

    source_names = ['ToolboxShared.swift', 'ToolboxBridge.swift', 'AppSettings.swift', 'LiveDesktopCard.swift', 'LiveReactions.swift', 'DesktopReactions.swift', 'ReactionModel.swift', 'AppUpdater.swift', 'StatusPopover.swift', 'WidgetSelfRepair.swift', 'MenuCustomization.swift', 'Model.swift', 'ResetCard.swift', 'Host.swift', 'Widget.swift']
    for name in source_names:
        obj(name, d({'isa': 'PBXFileReference', 'lastKnownFileType': 'sourcecode.swift',
                     'path': q('Sources/' + name), 'sourceTree': q('<group>')}))
    obj('app-product', d({'isa': 'PBXFileReference', 'explicitFileType': 'wrapper.application',
                         'path': q(APP_NAME + '.app'), 'sourceTree': 'BUILT_PRODUCTS_DIR'}))
    obj('widget-product', d({'isa': 'PBXFileReference', 'explicitFileType': 'wrapper.app-extension',
                            'path': q(WIDGET_NAME + '.appex'), 'sourceTree': 'BUILT_PRODUCTS_DIR'}))
    obj('products', d({'isa': 'PBXGroup', 'children': arr([ident('app-product'), ident('widget-product')]),
                      'name': 'Products', 'sourceTree': q('<group>')}))
    obj('icon-file', d({'isa': 'PBXFileReference', 'lastKnownFileType': 'image.icns',
                       'path': q('Assets/AppIcon.icns'), 'sourceTree': q('<group>')}))
    obj('main-group', d({'isa': 'PBXGroup', 'children': arr([ident(name) for name in source_names + ['icon-file', 'products']]),
                        'sourceTree': q('<group>')}))
    obj('icon-build', d({'isa': 'PBXBuildFile', 'fileRef': ident('icon-file')}))
    obj('app-resources', d({'isa': 'PBXResourcesBuildPhase', 'buildActionMask': '2147483647',
                           'files': arr([ident('icon-build')]), 'runOnlyForDeploymentPostprocessing': '0'}))

    target_sources = [('app', ['ToolboxShared.swift', 'ToolboxBridge.swift', 'AppSettings.swift', 'LiveDesktopCard.swift', 'LiveReactions.swift', 'DesktopReactions.swift', 'ReactionModel.swift', 'AppUpdater.swift', 'StatusPopover.swift', 'WidgetSelfRepair.swift', 'MenuCustomization.swift', 'Model.swift', 'ResetCard.swift', 'Host.swift']),
                      ('widget', ['Model.swift', 'ResetCard.swift', 'Widget.swift'])]
    for target, files in target_sources:
        is_widget = target == 'widget'
        builds = [obj(target + '-' + name, d({'isa': 'PBXBuildFile', 'fileRef': ident(name)})) for name in files]
        obj(target + '-sources', d({'isa': 'PBXSourcesBuildPhase', 'buildActionMask': '2147483647',
                                   'files': arr(builds), 'runOnlyForDeploymentPostprocessing': '0'}))
        obj(target + '-frameworks', d({'isa': 'PBXFrameworksBuildPhase', 'buildActionMask': '2147483647',
                                      'files': '()', 'runOnlyForDeploymentPostprocessing': '0'}))
        settings = {
            'PRODUCT_NAME': q(WIDGET_NAME if is_widget else APP_NAME),
            'PRODUCT_BUNDLE_IDENTIFIER': q(BUNDLE_ID + ('.Widget' if is_widget else '')),
            'INFOPLIST_FILE': q(target + '-Info.plist'),
            'CODE_SIGN_STYLE': 'Manual', 'CODE_SIGN_IDENTITY': q('-'), 'CODE_SIGNING_ALLOWED': 'YES',
            'ENABLE_APP_SANDBOX': 'YES' if is_widget else 'NO',
            'CODE_SIGN_ENTITLEMENTS': q(target + '.entitlements'),
            'LD_RUNPATH_SEARCH_PATHS': q('$(inherited) @executable_path/../Frameworks' +
                                       (' @executable_path/../../../../Frameworks' if is_widget else '')),
            'SWIFT_VERSION': '5.0', 'MACOSX_DEPLOYMENT_TARGET': '14.0', 'SDKROOT': 'macosx',
            'GENERATE_INFOPLIST_FILE': 'NO', 'ENABLE_HARDENED_RUNTIME': 'NO',
            'SWIFT_EMIT_LOC_STRINGS': 'YES', 'ALWAYS_SEARCH_USER_PATHS': 'NO',
            'SKIP_INSTALL': 'YES' if is_widget else 'NO',
        }
        if not is_widget:
            settings.update(updater_build.xcode_settings(ROOT, q))
        if is_widget:
            settings['APPLICATION_EXTENSION_API_ONLY'] = 'YES'
        configs = [obj(target + '-' + config, d({'isa': 'XCBuildConfiguration', 'buildSettings': d(settings), 'name': config}))
                   for config in ['Debug', 'Release']]
        obj(target + '-configs', d({'isa': 'XCConfigurationList', 'buildConfigurations': arr(configs),
                                   'defaultConfigurationIsVisible': '0', 'defaultConfigurationName': 'Release'}))

    obj('embed-build', d({'isa': 'PBXBuildFile', 'fileRef': ident('widget-product'),
                         'settings': d({'ATTRIBUTES': arr(['RemoveHeadersOnCopy'])})}))
    obj('embed', d({'isa': 'PBXCopyFilesBuildPhase', 'buildActionMask': '2147483647', 'dstPath': q(''),
                   'dstSubfolderSpec': '13', 'files': arr([ident('embed-build')]),
                   'name': q('Embed App Extensions'), 'runOnlyForDeploymentPostprocessing': '0'}))
    obj('proxy', d({'isa': 'PBXContainerItemProxy', 'containerPortal': ident('project'), 'proxyType': '1',
                   'remoteGlobalIDString': ident('widget-target'), 'remoteInfo': WIDGET_NAME}))
    obj('dependency', d({'isa': 'PBXTargetDependency', 'target': ident('widget-target'), 'targetProxy': ident('proxy')}))
    for target in ['app', 'widget']:
        phases = [ident(target + '-sources'), ident(target + '-frameworks')]
        if target == 'app':
            phases += [ident('app-resources'), ident('embed')]
        name = APP_TARGET if target == 'app' else WIDGET_NAME
        obj(target + '-target', d({
            'isa': 'PBXNativeTarget', 'buildConfigurationList': ident(target + '-configs'),
            'buildPhases': arr(phases), 'buildRules': '()',
            'dependencies': arr([ident('dependency')] if target == 'app' else []),
            'name': name, 'productName': name, 'productReference': ident(target + '-product'),
            'productType': q('com.apple.product-type.application' if target == 'app' else 'com.apple.product-type.app-extension'),
        }))
    project_settings = {'SWIFT_VERSION': '5.0', 'MACOSX_DEPLOYMENT_TARGET': '14.0', 'SDKROOT': 'macosx', 'ARCHS': q('arm64 x86_64')}
    configs = [obj('project-' + config, d({'isa': 'XCBuildConfiguration', 'buildSettings': d(project_settings), 'name': config}))
               for config in ['Debug', 'Release']]
    obj('project-configs', d({'isa': 'XCConfigurationList', 'buildConfigurations': arr(configs),
                            'defaultConfigurationIsVisible': '0', 'defaultConfigurationName': 'Release'}))
    obj('project', d({
        'isa': 'PBXProject', 'attributes': d({'LastUpgradeCheck': '2700'}),
        'buildConfigurationList': ident('project-configs'), 'compatibilityVersion': q('Xcode 14.0'),
        'developmentRegion': 'zh-Hans', 'hasScannedForEncodings': '0', 'knownRegions': arr(['en', q('zh-Hans')]),
        'mainGroup': ident('main-group'), 'productRefGroup': ident('products'), 'projectDirPath': q(''),
        'projectRoot': q(''), 'targets': arr([ident('app-target'), ident('widget-target')]),
    }))
    (PROJECT / 'project.pbxproj').write_text('// !$*UTF8*$!\n' + d({
        'archiveVersion': '1', 'classes': '{}', 'objectVersion': '56', 'objects': d(objects), 'rootObject': ident('project'),
    }), encoding='utf-8')

    common = {
        'CFBundleDevelopmentRegion': 'zh_CN', 'CFBundleShortVersionString': '1.4.1',
        'CFBundleVersion': datetime.datetime.now().strftime('%Y%m%d%H%M%S'),
        'CFBundleExecutable': '$(EXECUTABLE_NAME)', 'CFBundleIdentifier': '$(PRODUCT_BUNDLE_IDENTIFIER)',
        'CFBundleName': '$(PRODUCT_NAME)', 'LSMinimumSystemVersion': '14.0',
    }
    app = dict(common, CFBundlePackageType='APPL', CFBundleDisplayName=APP_NAME,
               CFBundleIconFile='AppIcon', LSUIElement=True, NSPrincipalClass='NSApplication',
               CFBundleURLTypes=[{'CFBundleURLName': BUNDLE_ID + '.navigation',
                                  'CFBundleURLSchemes': ['codexresets']}])
    widget = dict(common, CFBundlePackageType='XPC!', CFBundleDisplayName=APP_NAME,
                  NSExtension={'NSExtensionPointIdentifier': 'com.apple.widgetkit-extension'})
    configurations = [
        ('app-Info.plist', app), ('widget-Info.plist', widget), ('app.entitlements', {}),
        ('widget.entitlements', {'com.apple.security.app-sandbox': True, 'com.apple.security.network.client': True}),
    ]
    for name, value in configurations:
        (ROOT / name).write_bytes(plistlib.dumps(value))


def generate_icon():
    script = ROOT / 'Assets/GenerateIcon.swift'
    icon = ROOT / 'Assets/AppIcon.icns'
    if not icon.exists() or icon.stat().st_mtime < script.stat().st_mtime:
        run(['xcrun', 'swift', script, ROOT / 'Assets'], cwd=ROOT)
        run(['iconutil', '-c', 'icns', ROOT / 'Assets/AppIcon.iconset', '-o', icon])


def register_app(source, destination):
    destination.parent.mkdir(parents=True, exist_ok=True)
    run(['ditto', '--norsrc', source, destination])
    run(['xattr', '-cr', destination])
    run(['codesign', '--verify', '--deep', '--strict', destination])
    lsregister = '/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister'
    # Leave only the installed copy registered, so the gallery cannot select a temporary build.
    subprocess.run([lsregister, '-u', str(source)], check=False, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    subprocess.run(['pluginkit', '-r', str(source / 'Contents/PlugIns' / (WIDGET_NAME + '.appex'))],
                   check=False, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    run([lsregister, '-f', destination], stdout=subprocess.DEVNULL)
    run(['pluginkit', '-a', destination / 'Contents/PlugIns' / (WIDGET_NAME + '.appex')])


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--install', action='store_true', help='Copy and register the new app in ~/Applications')
    parser.add_argument('--generate-only', action='store_true', help='Generate project, plists and icon without building')
    arguments = parser.parse_args()
    generate_project()
    generate_icon()
    if arguments.generate_only:
        print('Generated:', PROJECT)
        return

    build = pathlib.Path(tempfile.mkdtemp(prefix='codexresets-build-'))
    run(['xcodebuild', '-project', PROJECT, '-target', APP_TARGET, '-configuration', 'Release',
         'SYMROOT=' + str(build), 'CODE_SIGN_IDENTITY=-', '-quiet'], cwd=ROOT)
    source = build / 'Release' / (APP_NAME + '.app')
    # Ship attribution with the native turbulence/glow adaptation, before signing.
    (source / 'Contents/Resources/ElectricBorder-MIT.txt').write_bytes((ROOT / 'Assets/ElectricBorder-MIT.txt').read_bytes())
    updater_build.finish(ROOT, source)
    run(['codesign', '--verify', '--deep', '--strict', source])
    output = source
    if arguments.install:
        output = pathlib.Path.home() / 'Applications' / (APP_NAME + '.app')
        register_app(source, output)
    delivery = ROOT / '交付'
    delivery.mkdir(exist_ok=True)
    archive = delivery / 'Codex重置-Mac.zip'
    run(['ditto', '-c', '-k', '--norsrc', '--keepParent', output, archive])
    checksum = hashlib.sha256(archive.read_bytes()).hexdigest()
    (delivery / 'SHA256SUMS').write_text(checksum + '  ' + archive.name + '\n', encoding='utf-8')
    record = {'app': str(output), 'build_app': str(source), 'archive': str(archive), 'sha256': checksum,
              'installed': arguments.install, 'bundle_id': BUNDLE_ID, 'widget_bundle_id': BUNDLE_ID + '.Widget'}
    (delivery / 'build-result.json').write_text(json.dumps(record, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
    print(json.dumps(record, ensure_ascii=False, indent=2))


if __name__ == '__main__':
    main()

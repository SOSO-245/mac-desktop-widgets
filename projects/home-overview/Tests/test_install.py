"""Installer fault-injection tests; all apps/files live in a temporary directory.

No command, process signal, registration, installed app or actual Keychain is used.
Run with: python3 -m unittest discover -s Tests -p 'test_install.py' -v
"""
import importlib.util
import json
import pathlib
import plistlib
import shutil
import subprocess
import tempfile
import unittest
from unittest import mock
import zipfile


PROJECT = pathlib.Path(__file__).resolve().parents[1]


def load_module(name, path):
    spec = importlib.util.spec_from_file_location(name, path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


class InstallerTests(unittest.TestCase):
    def setUp(self):
        self.scratch = tempfile.TemporaryDirectory(prefix='homeatlas-installer-test-')
        self.addCleanup(self.scratch.cleanup)
        self.root = pathlib.Path(self.scratch.name).resolve()
        self.installer = load_module('installer_under_test', PROJECT / 'Scripts/install.py')
        self.installer.ROOT = self.root / 'project'
        self.installer.ROOT.mkdir()
        self.installer.APPLICATIONS = self.root / 'Applications'
        self.installer.APPLICATIONS.mkdir()
        self.installer.DESTINATION = self.installer.APPLICATIONS / '家庭概览.app'
        self.old = self.installer.APPLICATIONS / '家庭用电.app'
        self.preview = self.installer.APPLICATIONS / '家庭概览预览.app'
        self.source = self.root / 'build' / '家庭概览.app'
        self.make_app(self.old, self.installer.BUNDLE_ID, '1.1.2', 'old-energy')
        self.make_app(self.preview, 'local.homeatlas.tvpreview.mac', '0.1.2', 'old-preview')
        self.make_app(self.source, self.installer.BUNDLE_ID, '2.0.0', 'new-overview')
        self.make_app(self.installer.widget(self.source), self.installer.WIDGET_ID, '2.0.0', 'new-widget')
        self.events = []
        self.failure = None
        self.failed_registration = False
        self.bad_signature_paths = set()
        patches = [
            mock.patch.object(self.installer, 'run', side_effect=self.fake_run),
            mock.patch.object(self.installer, 'processes', return_value={}),
            mock.patch.object(self.installer, 'stop', side_effect=lambda apps: self.events.append(('stop', tuple(apps)))),
            mock.patch.object(self.installer, 'unregister', side_effect=lambda app: self.events.append(('unregister', app))),
            mock.patch.object(self.installer, 'register', side_effect=self.fake_register),
            # A missed mock must fail instead of starting an actual OS command.
            mock.patch.object(subprocess, 'run', side_effect=AssertionError('Unexpected real subprocess')),
            mock.patch.object(self.installer.os, 'kill', side_effect=AssertionError('Unexpected real signal')),
        ]
        for patch in patches:
            patch.start()
            self.addCleanup(patch.stop)

    def make_app(self, path, identifier, version, contents):
        (path / 'Contents/MacOS').mkdir(parents=True)
        info = {'CFBundleIdentifier': identifier, 'CFBundleShortVersionString': version,
                'CFBundleURLTypes': [{'CFBundleURLSchemes': ['homeenergy', 'homeatlas']}]}
        (path / 'Contents/Info.plist').write_bytes(plistlib.dumps(info))
        (path / 'Contents/MacOS/TestBinary').write_text(contents)

    def snapshot(self):
        return {str(path.relative_to(self.installer.APPLICATIONS)): path.read_bytes()
                for path in self.installer.APPLICATIONS.rglob('*') if path.is_file()}

    def fake_register(self, app):
        self.events.append(('register', app))
        if self.failure == 'registration' and app == self.installer.DESTINATION and not self.failed_registration:
            self.failed_registration = True
            raise RuntimeError('Injected registration failure')

    def fake_run(self, args, *, check=True):
        args = [str(arg) for arg in args]
        self.events.append(('command', tuple(args)))
        if args[0] == 'codesign':
            path = pathlib.Path(args[-1])
            bad_replacement = (self.failure == 'destination_signature'
                               and path == self.installer.DESTINATION
                               and self.installer.metadata(path)['CFBundleShortVersionString'] == '2.0.0')
            if path in self.bad_signature_paths or bad_replacement:
                raise RuntimeError('Injected strict signature failure')
        elif args[:2] == ['ditto', '-c']:
            if self.failure == 'backup':
                raise RuntimeError('Injected backup failure')
            source, archive = map(pathlib.Path, args[-2:])
            with zipfile.ZipFile(archive, 'w') as output:
                for path in source.rglob('*'):
                    if path.is_file():
                        output.write(path, path.relative_to(source.parent))
        elif args[:2] == ['ditto', '-x']:
            archive, destination = map(pathlib.Path, args[-2:])
            with zipfile.ZipFile(archive) as source:
                source.extractall(destination)
        elif args[:2] == ['ditto', '--norsrc']:
            shutil.copytree(args[-2], args[-1], dirs_exist_ok=True)
        elif args[0] == 'unzip':
            with zipfile.ZipFile(args[-1]) as archive:
                if archive.testzip() is not None:
                    raise RuntimeError('Corrupted test backup')
        elif args[0] not in {'xattr', 'open'}:
            raise AssertionError(f'Unhandled mocked command: {args}')
        return subprocess.CompletedProcess(args, 0)

    def only_backup(self):
        backups = list((self.installer.ROOT / '备份').iterdir())
        self.assertEqual(len(backups), 1)
        return backups[0]

    def assert_rolled_back(self, previous):
        self.assertEqual(self.snapshot(), previous)
        manifest = json.loads((self.only_backup() / 'manifest.json').read_text())
        self.assertEqual(manifest['status'], 'rolled_back')
        self.assertFalse(self.installer.DESTINATION.exists())

    def test_source_failure_precedes_backup_or_old_app_changes(self):
        previous = self.snapshot()
        self.bad_signature_paths.add(self.source)
        with self.assertRaisesRegex(RuntimeError, 'strict signature'):
            self.installer.install(self.source, launch=False)
        self.assertEqual(self.snapshot(), previous)
        self.assertFalse((self.installer.ROOT / '备份').exists())
        self.assertFalse(any(event[0] == 'stop' for event in self.events))

    def test_backup_failure_does_not_stop_or_modify_old_apps(self):
        previous = self.snapshot()
        self.failure = 'backup'
        with self.assertRaisesRegex(RuntimeError, 'backup failure'):
            self.installer.install(self.source, launch=False)
        self.assertEqual(self.snapshot(), previous)
        self.assertFalse(any(event[0] in {'stop', 'unregister'} for event in self.events))

    def test_registration_failure_restores_both_original_apps(self):
        previous = self.snapshot()
        self.failure = 'registration'
        with self.assertRaisesRegex(RuntimeError, 'registration failure'):
            self.installer.install(self.source, launch=False)
        self.assert_rolled_back(previous)

    def test_destination_signature_failure_does_not_block_rollback(self):
        previous = self.snapshot()
        self.failure = 'destination_signature'
        with self.assertRaisesRegex(RuntimeError, 'strict signature'):
            self.installer.install(self.source, launch=False)
        self.assert_rolled_back(previous)

    def test_unexpected_installed_identity_is_never_touched(self):
        info = self.installer.metadata(self.old)
        info['CFBundleIdentifier'] = 'com.example.someone-else'
        (self.old / 'Contents/Info.plist').write_bytes(plistlib.dumps(info))
        previous = self.snapshot()
        with self.assertRaisesRegex(RuntimeError, 'Unexpected application identity'):
            self.installer.install(self.source, launch=False)
        self.assertEqual(self.snapshot(), previous)
        self.assertFalse((self.installer.ROOT / '备份').exists())
        self.assertFalse(any(event[0] == 'stop' for event in self.events))

    def test_installed_symlink_is_never_followed_or_removed(self):
        external = self.root / 'external.app'
        self.old.rename(external)
        self.old.symlink_to(external, target_is_directory=True)
        with self.assertRaisesRegex(RuntimeError, 'real app directory'):
            self.installer.install(self.source, launch=False)
        self.assertTrue(self.old.is_symlink())
        self.assertEqual((external / 'Contents/MacOS/TestBinary').read_text(), 'old-energy')
        self.assertFalse(any(event[0] == 'stop' for event in self.events))

    def test_success_then_manual_rollback_preserves_original_bytes(self):
        previous = self.snapshot()
        self.installer.install(self.source, launch=False)
        self.assertFalse(self.old.exists())
        self.assertFalse(self.preview.exists())
        self.assertTrue(self.installer.DESTINATION.is_dir())
        self.installer.rollback(self.only_backup(), launch=False)
        self.assertEqual(self.snapshot(), previous)

    def test_rollback_refuses_wrong_identity_before_removing_any_app(self):
        self.installer.install(self.source, launch=False)
        info = self.installer.metadata(self.installer.DESTINATION)
        info['CFBundleIdentifier'] = 'com.example.someone-else'
        (self.installer.DESTINATION / 'Contents/Info.plist').write_bytes(plistlib.dumps(info))
        previous = self.snapshot()
        with self.assertRaisesRegex(RuntimeError, 'Unexpected application identity'):
            self.installer.rollback(self.only_backup(), launch=False)
        self.assertEqual(self.snapshot(), previous)


class BuildRegistrationTests(unittest.TestCase):
    def test_cleanup_targets_only_the_passed_build_product(self):
        builder = load_module('builder_under_test', PROJECT / 'build.py')
        app = pathlib.Path('/tmp/homeatlas-test-output/Release/家庭概览.app')
        with mock.patch.object(builder.subprocess, 'run') as run:
            builder.unregister_build_product(app)
        self.assertEqual(len(run.call_args_list), 2)
        self.assertEqual(run.call_args_list[0].args[0][-2:], ['-u', str(app)])
        self.assertEqual(run.call_args_list[1].args[0],
                         ['pluginkit', '-r', str(app / 'Contents/PlugIns/HomeEnergyWidget.appex')])
        self.assertFalse(any('/Applications/' in str(call) for call in run.call_args_list))


if __name__ == '__main__':
    unittest.main()

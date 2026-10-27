#!/usr/bin/env python3
"""Keep independent app bundles in sync with the canonical settings UI."""
import argparse
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
PROJECTS = {
    'vpn-card': 'FlClash实时小组件', 'nikki-card': 'Nikki实时小组件',
    'codex-resets': 'Codex重置小组件', 'home-overview': 'Mac家庭概览',
    'lunar-calendar': 'Mac万年历', 'mac-vitals': 'Mac实时监测',
}
FILES = ('AppSettings.swift', 'MenuCustomization.swift', 'StatusPopover.swift', 'AppUpdater.swift')

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--check', action='store_true')
    parser.add_argument('--local-workspace', type=Path)
    args = parser.parse_args()
    mismatches = []
    for name in FILES:
        source = ROOT/'shared/settings'/name
        expected = source.read_bytes()
        targets = [ROOT/'projects'/slug/'Sources'/name for slug in PROJECTS]
        if args.local_workspace:
            targets += [args.local_workspace/folder/'Sources'/name for folder in PROJECTS.values()]
        if name == 'AppUpdater.swift': targets += [ROOT/'shared/updater'/name]
        for target in targets:
            if not target.exists() or target.read_bytes() != expected:
                if args.check:
                    mismatches.append(str(target.relative_to(ROOT)) if target.is_relative_to(ROOT) else str(target))
                else:
                    target.parent.mkdir(parents=True, exist_ok=True)
                    target.write_bytes(expected)
    if mismatches:
        raise SystemExit('Shared settings drift:\n'+'\n'.join(mismatches))
    print('Shared settings copies are consistent.' if args.check else 'Shared settings synchronized.')

if __name__ == '__main__': main()

#!/usr/bin/env python3
"""Synchronize layout-only shared source; no application state changes."""
from pathlib import Path
import shutil
root=Path(__file__).resolve().parents[1]
for slug in ['lunar-calendar','codex-resets','vpn-card','nikki-card','mac-vitals']:
 for name in ['ToolboxShared.swift','ToolboxBridge.swift']:
  shutil.copy2(root/'shared/toolbox'/name,root/'projects'/slug/'Sources'/name)
shutil.copy2(root/'shared/toolbox/ToolboxShared.swift',root/'projects/desktop-toolbox/Sources/ToolboxShared.swift')
print('Layout-only shared sources synchronized')

# API Usage has its own bridge adapter; share only the layout model.
shutil.copy2(root/'shared/toolbox/ToolboxShared.swift',root/'projects/api-usage/Sources/ToolboxShared.swift')

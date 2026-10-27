# Independent applications, shared settings UI

Each of the six applications owns one settings window. Apps, bundle identifiers,
processes, data directories, Keychain records and update feeds remain independent.

The canonical files in this directory provide the window/sidebar, menu-bar style
editor, desktop/popover appearance, and Sparkle settings. Each app supplies pages
and callbacks that reuse its existing controllers; opening a settings page must
not create a second data store, request a permission, change a connection, or reset
existing preferences. Navigation has its own `settings.selectedPage.v1` key in
each application's existing defaults domain.

`scripts/sync_shared_settings.py` distributes these four files into the independent
projects so each source package can still build on its own. Its `--check` mode
rejects divergent copies. `shared/updater/AppUpdater.swift` remains a checked copy
for existing updater tooling. Make shared changes here, then synchronize.

Display controls save immediately. Connection credentials and server changes keep
their original explicit validation and save action. Visited settings pages retain
unsaved fields while navigating within the same window. Quick actions such as
refresh, source switching, node selection and opening a calendar remain outside
the settings hierarchy.

The menu and desktop card expose `设置…`; old settings callbacks route into the
same window rather than creating separate appearance or menu-editor windows.

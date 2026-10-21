# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

A Q-Sys plugin (Lua) that synchronises components between two Q-Sys cores over TCP using the QRC JSON-RPC protocol (default port 1710). The local core acts as a client to a remote core, mirroring control state in both directions for selected components. The original use case is running UCI code on a separate core from the main DSP program.

## Build / deploy

Source files are concatenated by the compiler — **never edit `q-sys-plugin-remote-sync.qplug` directly**. It is regenerated from `plugin.lua` and its `#include` files.

The VS Code build chain (`.vscode/tasks.json`) runs three steps in sequence:

1. **Version bump** (`plugincompile/compile_plugin.sh <ver_inc>`) — bumps `BuildVersion` in `info.lua`. `<ver_inc>` is one of `ver_maj`, `ver_min`, `ver_fix`, `ver_dev`, or `ver_none` (no bump). Also generates a UUID for the plugin `Id` field if it is still `<guid>`.
2. **Compile** (`plugincompile/PLUGCC.exe <basename> plugin.lua`) — resolves the `#include` directives in `plugin.lua` and writes `<basename>.qplug`.
3. **Deploy** (`plugincompile/copy_plugin.cmd <workspaceFolder> <basename>`) — copies the `.qplug` into `%USERPROFILE%\Documents\QSC\Q-Sys Designer\Plugins\<basename>\`.

Run via VS Code "Compile QSD Plugin" task (default build task). The compile shell requires `sh` (Git Bash / WSL) on PATH because `compile_plugin.sh` is shell.

There are no automated tests. Validation is manual in Q-Sys Designer using the `tests/*.qsys` design files (one acts as the local UI core, one as the remote system core). `tests/q-sys-plugin-remote-sync-DEV-UI.qplug` is a debug-friendly copy of the plugin generated per the QSC ["Debugging Run-time Code"](https://q-syshelp.qsc.com/DeveloperHelp/) workflow.

## Plugin architecture

`plugin.lua` is a thin shim of Q-Sys lifecycle entry points (`GetProperties`, `GetControls`, `GetPages`, `GetControlLayout`, `GetPins`, `RectifyProperties`). Each one `#include`s a sibling file (`properties.lua`, `controls.lua`, etc.). Runtime logic lives entirely under `if Controls then ... #include "runtime.lua" end` — the same file is invoked once for design-time metadata and again at runtime.

`info.lua` exposes globals (`PluginInfo`, `PrettyName`, `PageNames`, `DefaultColor`) that the other files read. `PageNames = {"Setup","System","Devices"}` drives both `pages.lua` and the `if(CurrentPage == ...)` branches in `layout.lua`.

The `Component Count` integer property (default 2, max 255) determines `Count` on every component-selector control array (`LocalComponents`, `RemoteComponents`, `CommonComponents`, `LocalControls`, `RemoteControls`, `CommonControls`, `SyncComponent`). Index `i` across these arrays always refers to the same logical sync pairing.

## Runtime architecture (`runtime.lua`)

Single TCP socket to the remote core speaking QRC JSON-RPC. All outbound writes go through `commandQueue` via `Enqueue` / `Dequeue` / `Write` — the queue serialises writes and only drains when the socket is connected and `(LoggedIn or not LoginRequired)`. Inbound bytes append to `rxBuffer`; `BufferTimer` (1 ms) drives `ProcessBuffer` → `GetRxBufferBlock` (balanced-brace JSON extractor) → `ParseResponse`.

Key state tables (all module-level):

- `LocalComponents[name]` — `Component.New()` handles for components on this core.
- `LocalControls[name]` — controls list per local component (lazy-populated to avoid Max execution errors).
- `LocalCodeBackup[name]` — backup of script `code` strings before `ClearLocalCode` wipes them; restored when toggled off.
- `RemoteComponents` — array as returned by remote `Component.GetComponents`.
- `RemoteControls[component][controlName]` — current remote control values; populated by `Component.GetControls` responses and `ChangeGroup.Poll` change events.
- `RemoteSubscriptions[component][controlName]` — tracks which remote controls we have already added to the change group (dedup).
- `LocalSelectors[name]` / `RemoteSelectors[name]` — reverse index from a component name to the selector indices `i` (1..ComponentCount) currently pointing at it. Same name can appear in multiple selectors.
- `subscriber[localScript][remoteComponent]` — forwards remote change events to local scripts that registered via `ChangeGroup.AddComponentControl` (used for local scripts that need to listen to remote controls).
- `messageIDs[id]` — stores outbound request payload so the response handler can dispatch by `method`.
- `SyncComponentQueue` + `SyncComponentTimer` (5 ms tick) — queue of remote→local updates applied one control at a time to avoid Q-Sys Max execution errors.

Single change group identified by `ChangeGroup = tostring(math.random(255))`, polled at `PollRate = 0.5 s` via `ChangeGroup.AutoPoll`.

### Response dispatch
`ParseResponse` decides routing by `data.id` format:
- Numeric `id` → response to a request from this plugin; looked up in `messageIDs[id]` and dispatched by `tbl_.method` (`Logon`, `Component.GetControls`, `Component.GetComponents`, `ChangeGroup.AddComponentControl`, `ChangeGroup.AutoPoll`, `Component.Set`).
- `id` of form `"<componentName>-<n>"` → response to a subscription request originating from a local script; forwarded to `Component.New(componentName).StringFromRemoteQSYS.String`.
- `data.method == "ChangeGroup.Poll"` → `HandleRemoteChangeGroupData` populates `RemoteControls` + `SyncComponentQueue` and notifies any local subscriber scripts via `UpdateLocalSubsriberScripts`.

### Local script bridge
Local scripts can interact with the remote core by:
1. Setting `Controls.StringToSend.String` on the plugin — content is appended to `subscribersBuffer` and forwarded to the remote.
2. Receiving forwarded remote responses on their own `StringFromRemoteQSYS` control (must exist on the local script).

### Sync filtering rules
- Only writable controls are synced (read-only status controls are skipped via pcall failures in `SyncControl`).
- Built-in script controls matching `^log.%w`, `^script.%w`, `^halt.%w`, `^magic.number`, `^reload` (in `sysControlNames`) are never synced.
- `code` is gated by `Controls.EnablePullingCode.Boolean` (remote→local) and `Controls.EnablePushingCode.Boolean` (local→remote); both default off to avoid clobbering scripts.
- `ClearLocalCode` writes a sentinel string to local `code` controls and backs up the original to `LocalCodeBackup`; toggling off restores from backup or pulls from remote.
- Caveat referenced in code/README: do **not** put `$` at the end of a `sysControlNames` pattern — the compiler converts `$` to `end` and breaks the `.qplug`.

### Common-components pattern
`Controls.CommonComponents[i]` is a convenience selector: setting it auto-populates `LocalComponents[i]` and `RemoteComponents[i]` with the same name. `UpdateCommonComponents` builds its choice list from the intersection of local and remote components. `UpdateCommonControls(i)` then computes the intersection of control names and subscribes to those on the remote via `ChangeGroup.AddComponentControl`.

## Debug controls

`Properties["Debug Print"]` enum (`None`, `Tx/Rx`, `Tx`, `Rx`, `Function Calls`, `All`) sets the boolean controls `DebugTx`, `DebugRx`, `DebugFunction` at startup. These can also be toggled live on the plugin UI. `DebugPattern` (currently `'^Selector'`) is a hard-coded regex inside `runtime.lua` for filtering noisy per-control debug prints — edit it when targeting a specific control type.

## Conventions

- Indent is 2 spaces (`.vscode/settings.json`).
- Lua files end without a trailing newline policy enforced; `compile_plugin.sh` runs `unix2dos -q info.lua` to normalise line endings on `info.lua` specifically.
- `pins.lua` and `rectify_properties.lua` exist but are minimal/empty — leave the `#include` shims in place.

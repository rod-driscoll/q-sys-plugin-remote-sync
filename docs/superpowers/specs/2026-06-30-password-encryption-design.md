# Password encryption for Controls.Password.String

## Goal

Apply the project-standard XOR password-encryption pattern (`patterns/password-encryption.md`) to the Remote Sync plugin so that the user-entered password is never stored in plaintext in `SecretStorage` and never visible in `Controls.Password.String` after entry.

## Why

Q-SYS `SecretStorage` is plaintext at rest, and any Lua script in the same design can enumerate plugin controls. The plugin currently passes `Controls.Password.String` directly to `Logon(...)` and uses no `SecretStorage` at all — so the password sits in a UserPin'd text control where anyone with design access can read it. The pattern XOR-encrypts the password (key = `PluginInfo.Id`) before storage and masks the visible control.

## Scope

All edits land in `runtime.lua`. No changes to `controls.lua`, `info.lua`, layout, or properties.

## Changes

1. **Module-level constants** (top of `runtime.lua`, near existing locals around line 8):
   - `local ENC_KEY = PluginInfo.Id`
   - `local MySecret` (declared, assigned later in `InitialiseCore`)

2. **Helper block** (after the variables section, before `SetupDebugPrint`):
   - `byteXor(a, b)` — pure-Lua XOR
   - `ENC_PREFIX = "ENC:"`
   - `encryptPassword(plaintext)` — returns `ENC:<hex>`
   - `decryptPassword(stored)` — returns plaintext; if missing prefix, returns input unchanged (legacy/plaintext passthrough)

3. **Startup migration + display mask** inside `InitialiseCore()` (currently ends ~line 1009):
   ```lua
   MySecret = SecretStorage["text.1"]
   if MySecret.String ~= "" then
     if MySecret.String:sub(1, #ENC_PREFIX) ~= ENC_PREFIX then
       MySecret.String = encryptPassword(MySecret.String)
     end
     Controls.Password.String = string.rep("*", 8)
   end
   ```

4. **EventHandler replacement** at [runtime.lua:1005](../../runtime.lua#L1005):
   ```lua
   Controls.Password.EventHandler = function(ctrl)
     MySecret.String = encryptPassword(ctrl.String)
     ctrl.String = string.rep("*", 8)
     LoggedOut()
   end
   ```
   `LoggedOut()` is retained so editing the password still forces a re-login (preserves current behaviour where `Controls.Password.EventHandler = LoggedOut`).

5. **Point-of-use decryption** at both Logon call sites:
   - [runtime.lua:714](../../runtime.lua#L714): `Password = decryptPassword(MySecret.String)`
   - [runtime.lua:915](../../runtime.lua#L915): `['Password'] = decryptPassword(MySecret.String)`

## Filter caveat

Per `CLAUDE.md` and the pattern note: `$` in a Lua pattern would be rewritten to `end` by the compiler. None of the new code uses `$` in a Lua pattern. The `^` in `stored:sub(1, #ENC_PREFIX) ~= ENC_PREFIX` is a `string.sub` index, not a pattern, so the documented `find("^"..ENC_PREFIX, 1, true)` bug does not apply.

## Migration behaviour

`decryptPassword` returns its input unchanged when the prefix is missing, so any plaintext already in `SecretStorage["text.1"]` is silently upgraded on first load. The plugin doesn't currently write to `SecretStorage`, so in practice nothing needs migrating, but the guard is harmless.

## Out of scope

- Encrypting `Controls.Username.String` (not sensitive at rest in the same way).
- Replacing the XOR cipher with anything stronger — the pattern is the project standard and the threat model is "other in-design Lua scripts", not a determined attacker with disk access.
- Backporting older builds.

## Validation

Manual in Q-SYS Designer using `tests/*.qsys`:
1. Enter a password — control should immediately display 8 asterisks.
2. Reload the script — control should display 8 asterisks again (not blank, not plaintext).
3. Enumerate components from a sibling Lua script — `text.1` should appear as `ENC:<hex>`, not plaintext.
4. Trigger Logon — remote core should accept the credentials (proving decryption round-trips correctly).
5. Edit the password — `LoggedIn` should drop to false and a new Logon should fire.

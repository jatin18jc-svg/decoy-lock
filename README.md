# Decoy Lock

By Jatin Chutani.

A free macOS helper that locks `.xlsx`, `.docx`, `.pptx` and `.pdf` files with two passwords.

- **Real password**: the file opens in its usual app with everything in it.
- **Decoy word**: the same app opens a blank file with the same name, so the file seems empty.
- **Anything else**: "Incorrect password".

A locked file keeps its name, extension and icon. `Budget.xlsx` stays `Budget.xlsx`. Decoy Lock never becomes the default app for a file type: only the files you lock open through it, and everything else opens exactly as before.

The windows only you see (setup, locking, settings, the menu bar) star a small document with possum ears. It covers its eyes while you type your real password and plays dead while you type your decoy word. The password box anyone else might see is plain and looks like a system dialog, with no mascot and no app name.

## Download

Get **Decoy-Lock-1.0.dmg** from the [latest release](https://github.com/jatin18jc-svg/decoy-lock/releases/latest). Open it, drag Decoy Lock to Applications, and follow "Read Me First" inside. Because the app isn't notarized, the first launch needs **System Settings > Privacy & Security > Open Anyway**, once. Needs macOS 14 or later, on Apple silicon or Intel.

To build it yourself instead, read on.

## Install from source

You need macOS 14 or later and the Xcode Command Line Tools (`xcode-select --install`). Full Xcode isn't needed.

```bash
./install.sh
```

That builds a universal app (Apple silicon and Intel), signs it ad hoc, copies it to `/Applications`, registers it with Launch Services and opens it. To build without installing, use `./build.sh`. To build and run the self-test, use `./build.sh --test` (add `--large` for the 100 MB case).

A copy built on your own Mac opens without warnings.


## First run

Setup walks through three steps:

1. A short demo of what each kind of password does.
2. **Choose your pair**: your real password (at least 8 characters, typed twice) and your decoy word. The pair is saved in your login Keychain.
3. Choose whether Decoy Lock opens at login and whether to show the menu bar icon.

Decoy Lock has no Dock icon. To get back to Settings, click the menu bar icon, or open Decoy Lock from Applications again (handy if you've hidden the menu bar icon).

## Locking a file

- Right-click the file in Finder and choose **Services > Lock with Decoy Lock**. On some macOS versions it appears under **Quick Actions** instead.
- Or drop files onto the menu bar icon, or into its popover.
- Or click the menu bar icon and choose **Choose Files to Lock…**

The lock window uses your usual pair. Tick **Use a different pair** to lock files with a one-off pair; Decoy Lock doesn't remember that pair, so keep it somewhere safe.

The file is rewritten in place: same path, same name, same creation and modification dates, same Finder tags. It's also set to open in Decoy Lock, for that one file only. This is the same setting Finder makes when you change **Get Info > Open with** for one file without clicking Change All. It stays with the file through edits, and it travels with the file to another Mac that has Decoy Lock. The locked version is decrypted and checked before it replaces the original. A file that's already locked, isn't a real file of its type, or is open in another app is left alone, and the window says why.

## Opening, editing and saving

Double-click as usual. Normal files open in their usual app; Decoy Lock isn't involved at all. Locked files open in Decoy Lock, which shows the password box first.

If a locked file opens in Excel or Preview as "damaged", it has lost its per-file setting (some cloud services and email attachments drop it). If macOS says it "could not verify" the file is free of malware, the file carries macOS's "downloaded from the internet" flag, which macOS won't let an app that isn't notarized open. Either way, drop the file on the menu bar icon: Decoy Lock sees it's already locked and fixes both.

Files you download keep that protection. When you lock one, the flag is moved inside the encrypted file and put back on the unlocked copy, so apps like Office still open it in Protected View.

With the real password, Decoy Lock writes an unlocked copy to a private temp folder (only your user can read it) and opens it in the usual app. Each time you save, the new contents are encrypted back into the locked file at its original path, and the decoy half is kept as it was. When the app lets go of the copy, the copy is deleted.

With the decoy word you get a blank copy, and any edits to it are thrown away.

## Settings

- **Your pair**: **Show Pair** displays your usual pair and any earlier ones after Touch ID or your Mac password. **Change Pair** asks for the current real password, or Touch ID if you've forgotten it. A new pair only affects files you lock afterwards; files you've already locked keep their old pair, which Show Pair still lists.
- **Opening files**: shows which app unlocked copies open in. Decoy Lock passes them to whatever app is the default for that type.
- **Looks**: hide the menu bar icon; give locked files a blank-page thumbnail (see below).
- **Startup**: open at login.
- **Uninstall**: see below.

## Uninstall

Open **Settings > Uninstall Decoy Lock…**. It turns off the login item, deletes the saved pair from the Keychain and moves the app to the Trash. It doesn't unlock anything, and locked files won't open without Decoy Lock. To keep an unlocked copy of a file, open it with the real password and use **File > Save As** in its app before you uninstall.

## Known limits

- **Forgotten passwords.** The encryption has no back door, so a password is the only way in. Your usual pair (and every earlier usual pair) is kept in your login Keychain, and **Settings > Show Pair** displays them after Touch ID or your Mac password. **Change Pair** also accepts Touch ID if you've forgotten the current one. A one-off pair you set for a single file isn't stored anywhere, so a forgotten one-off pair can't be recovered. Uninstalling deletes the saved pairs.
- **On a Mac without Decoy Lock, a locked file looks damaged** and won't open.
- **This protects against someone looking over your shoulder, not a forensic investigation.** Someone with time and tools can tell the file is encrypted (it doesn't parse as an Office file or PDF), and a locked file is roughly twice the size of the original.
- **Backups keep old versions.** Time Machine, iCloud Drive version history and other backups made before you locked a file still hold it unlocked.
- **Get Info shows Decoy Lock under "Open with" for a locked file**, while a normal file of the same type shows Excel (or Word, PowerPoint, Preview). It's the one place the difference shows, and only if someone opens Get Info.
- **Opening a locked file from inside the app** (File > Open, or the Recent list in Excel) skips Decoy Lock, and the app says the file is damaged. Open locked files from Finder.
- **Recent-file lists show the temp copy.** Office's Recents (and File > Open Recent in other apps) list the unlocked copy's temp path, which stops working once it's cleaned up. Someone browsing your Recents could see that the file was opened from a temp folder.
- **Microsoft Office may ask for file access** the first time you save an unlocked copy, because the copy lives in a temp folder. Click **Grant Access**.
- **Spacebar preview (Quick Look)** can't show a locked file, so it shows the type's icon, or the blank thumbnail if that's turned on. Finder also shows content thumbnails for normal files and a plain icon for locked ones. The **blank-page thumbnail** option fixes that for newly locked files by giving them the thumbnail of an empty page. It's off by default because it adds a custom icon to the file, which shows in Get Info.
- **The usual pair is stored in your login Keychain.** The brief asked for only a verifier, but locking new files with the usual pair needs the passwords themselves (each file gets new random salts). The Keychain encrypts them at rest, and nothing is ever written in plain text. After a rebuild, macOS may ask once whether Decoy Lock can use the Keychain item; choose **Always Allow**.
- **If Decoy Lock quits while a real file is open**, later saves stay in the temp copy and don't reach the locked file. Quitting from the menu warns you about this.
- The app is signed ad hoc, not notarized.

## Security

### What it does to keep files safe

- **Encryption**: AES-256-GCM, with keys from PBKDF2-HMAC-SHA256 (310,000 rounds, a fresh random salt per file half), all from Apple's own CryptoKit and CommonCrypto. If someone changes a single byte of a locked file, it simply won't open.
- **Nothing to read**: a locked file holds no name, marker or readable text, and its real and decoy halves are the same size. Opening with the real password and with the decoy word takes the same time.
- **Typing is protected**: the password box uses macOS secure text entry, which stops other apps from reading your keystrokes.
- **Unlocked copies** live in a temp folder only your account can open, and are deleted once the app closes them.
- **Saved pairs** sit in your login Keychain, and Show Pair asks for Touch ID or your Mac password.
- **Hardened runtime** is on, so other programs can't inject code into Decoy Lock or attach a debugger to read its memory.
- **No internet**: the app never connects to the network, and it collects and sends nothing.

### Where an unlocked copy can still exist

- **Before you locked it**: Time Machine, iCloud version history and APFS snapshots may hold the original, and the disk blocks it used aren't overwritten. **Turn on FileVault** (System Settings > Privacy & Security > FileVault) so none of that can be read off the disk without your Mac password.
- **While it's open**: Office saves AutoRecovery copies in its own folder as you work (they're normally deleted when you close the file), and anything you Save As, copy or export is an ordinary unlocked file.
- **Recent lists** in Office and other apps show the temp copy's path.

### How strong the real password needs to be

Someone who copies a locked file can try passwords on their own computer as fast as their hardware allows, and no app setting can slow that down. Each guess costs them a little work, but a short or common password can still fall in hours. New pairs need at least 8 characters; for anything important, use four or five random words or 12+ mixed characters. The decoy word can be simple, since it only ever opens a blank file.

### Compared with a typical Mac app

| A typical Mac app | Decoy Lock |
| --- | --- |
| Signed with a Developer ID and notarized by Apple | Signed ad hoc. Notarizing needs a paid Apple Developer account ($99 a year). Until then, a downloaded copy needs **Open Anyway** once. |
| Hardened runtime | Yes |
| App Sandbox | No. It's only required on the Mac App Store, and Decoy Lock has to rewrite files where they are and watch the copies apps save. |
| Automatic updates | No. To update, send a new disk image; installing it over the old app keeps your pairs. |
| Network access | None |

## How it works

### File format

```
[blob A][blob B]                       order picked at random at lock time
blob      = salt (16 bytes) | nonce (12) | AES-256-GCM ciphertext | tag (16)
plaintext = u32 header length | JSON header {v, name, type, size, dk} | file bytes | random padding
```

- Keys come from PBKDF2-HMAC-SHA256 (CommonCrypto, 310,000 iterations, one salt per blob). Encryption is AES-256-GCM from CryptoKit. No third-party code.
- Both blobs are padded to the same length (at least 64 KB, then in steps of about 12%), so each is exactly half the file and nothing says which is real.
- There's no magic number or marker. A file is treated as locked when it doesn't start with its type's real signature (`PK\x03\x04` or Office's own encrypted container for Office files, `%PDF-` for PDFs) and its length is even.
- `dk` is how edits get saved without the decoy word. In the real blob it holds the decoy blob's key; in the decoy blob it's random bytes. Both headers have the same shape. When the real password opens a blob, its `dk` also opens the other blob, which tells Decoy Lock it's the real one.
- Every attempt does the same work in the same order, and the password box always waits at least 0.55 s, so the real password and the decoy word take the same time and close the box the same way.
- The decoy content is a blank file shipped inside the app bundle, generated at build time by `tools/make_decoys.py`.

### Code map

| Path | What's there |
| --- | --- |
| `Sources/DecoyLock/Core/FileTypes.swift` | The table of supported types |
| `Sources/DecoyLock/Core/LockedFormat.swift` | Key derivation, encryption, the file layout, re-saving |
| `Sources/DecoyLock/Core/Locker.swift` | Locking a file in place, the per-file opener, the blank thumbnail |
| `Sources/DecoyLock/Core/SessionManager.swift` | Temp copies, save watching, write-back, cleanup |
| `Sources/DecoyLock/Core/DefaultApps.swift` | Which app unlocked copies open in |
| `Sources/DecoyLock/Core/Storage.swift` | Settings, the Keychain pair, password rules, login item |
| `Sources/DecoyLock/UI/` | The mascot, password box, setup, lock window, menu bar, settings |
| `Sources/DecoyLock/App/` | App delegate, windows, build tools, self-test, snapshots |

### Adding a file type

1. Add a row to `FileTypes.all` (extension, UTI, signatures, decoy file name, preferred apps). `Info.plist` is generated from this table at build time, so the document type and Services entry follow.
2. Add a blank decoy file to `tools/make_decoys.py`.
3. Rebuild and run `./build.sh --test`.

### Design notes

- One mascot carries the personality. Everything around it is native macOS: system controls, grouped forms, standard alerts.
- Palette: possum fur `#E9E5EF`, deep ink `#2B2433`, dusk `#6B6285`, nose pink `#B13E66` for actions and `#EE86A6` on the mascot, moss `#4C6A42` for success. Light and dark variants live in `UI/Theme.swift`.
- Type: SF Pro Rounded for headings, so they match the mascot's soft shapes; SF Pro for everything else.
- To review the screens, run `"build.noindex/Decoy Lock.app/Contents/MacOS/DecoyLock" --snapshot /tmp/decoy-snaps`. It renders every screen in light and dark mode, plus each mascot mood, to PNG.

## Building notes

`build.sh` uses `swiftc` directly, so it runs with only the Command Line Tools. The newer SDK declares SwiftUI's `@State` as a macro whose compiler plugin ships only with full Xcode, so the code uses `@ViewState`, a type alias for the same property wrapper.

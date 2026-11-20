# Decoy Lock for Mac: build brief

Paste this into Claude Code as the brief for the project (or save it as `CLAUDE.md` in an empty folder and tell Claude Code to build it).

## What it does

A free macOS app that locks files with two passwords:

- **Real password** opens the real file in its normal app (Excel, Word, Preview).
- **Decoy word** opens an empty file of the same type in that same app, so it looks like the file has nothing in it.
- **Any other password** shows "Incorrect password".

The locked file must look like any normal file: **same name, same extension, same icon** as an unlocked file of that type. `Budget.xlsx` stays `Budget.xlsx`.

## Scope for v1

- File types: `.xlsx`, `.docx`, `.pptx`, `.pdf`. Build it so more types can be added through a single table in the code.
- macOS 14 and later, Apple silicon and Intel.
- Personal use, distributed free. No App Store and no sandbox. Ad-hoc code signing (`codesign -s -`) is enough to run it on my own Mac.
- Swift and SwiftUI, built with Xcode or `xcodebuild` from the command line. No third-party dependencies for the encryption.

## How it works

### 1. The app opens these file types by default

- The app declares `CFBundleDocumentTypes` for each supported type, using the standard UTIs (`org.openxmlformats.spreadsheetml.sheet`, `org.openxmlformats.wordprocessingml.document`, `org.openxmlformats.presentationml.presentation`, `com.adobe.pdf`).
- On first launch, a setup screen asks permission and makes the app the default opener for those types (`NSWorkspace.setDefaultApplication(at:toOpen:)`). It first records the current default app for each type, such as Excel, so files can be handed on to it.
- The app runs as a background helper with `LSUIElement = YES`: no Dock icon, and an optional menu bar icon for settings.

### 2. Opening any file goes through the app

When a file is opened (`application(_:open:)`):

1. **Check whether it's a normal file.** If it starts with the real signature for its type (`PK\x03\x04` for Office files, `%PDF-` for PDFs), it's unlocked. Hand it straight to the recorded original app with `NSWorkspace.open(_:withApplicationAt:configuration:)`. No password box, nothing visible. This has to be fast enough that opening normal files feels the same as before.
2. **Otherwise, treat it as locked.** Show a small, plain password window: no branding, just "Enter password to open this file."
3. Try the password against both encrypted blobs in the file (format below).
   - If the real blob decrypts, write the real file to a private temp folder and open it in the original app.
   - If the decoy blob decrypts, write an empty file of the same type, with the same name, and open it the same way.
   - If neither decrypts, show "Incorrect password".
4. Both outcomes must look identical to someone watching: same window, same timing, same app opening, same file name in the title bar.

### 3. Locking a file

- A Finder Quick Action ("Lock with Decoy Lock") plus drag-and-drop onto the menu bar icon.
- It asks for the real password and the decoy word the first time, and uses the saved pair after that. Store the pair's verifier in the Keychain, never in plain text. Offer an option to set a different pair for one file.
- It rewrites the file in place: same path, same name, same extension. Keep the original creation and modification dates if possible.
- Delete the original contents safely: write the locked file to a temp file, then atomically replace the original.

### 4. Editing and saving

This is easy to miss. When the real file is open in Excel and I save changes, the changes land in the temp copy, not the locked file. The app has to:

- Watch the temp file (with a `DispatchSource` file watcher or FSEvents).
- On every save, re-encrypt the new contents back into the locked file at the original path, using the same two passwords and keeping the same decoy blob.
- Delete the temp copy once the app has closed it, by polling `lsof` or checking whether the document is still open, and also on the helper's next launch.
- Edits to the decoy file are thrown away and never written back.

### 5. Locked file format

No magic header and no readable marker, so the file gives nothing away.

```
[blob A][blob B]   (order randomised at lock time)
each blob = salt (16 bytes) | nonce (12 bytes) | AES-GCM ciphertext + tag
```

- Key derivation: PBKDF2-HMAC-SHA256 through CommonCrypto (`CCKeyDerivationPBKDF`), at least 310,000 iterations, one salt per blob. Encryption: AES-256-GCM through CryptoKit.
- Plaintext of each blob: `[u32 header length][JSON header {name, type, size}][file bytes][random padding]`.
- Pad both blobs to the same length so it's impossible to tell which one is real. Since they're equal, each blob is exactly half the file, and no length marker is needed.
- Ship ready-made empty `.xlsx`, `.docx`, `.pptx` and `.pdf` files in the app bundle as the decoy content.

## Must look like a normal file (acceptance tests)

Test each of these with one locked file and one unlocked file of the same type, side by side in Finder:

1. **Icon:** they look the same in Finder (icon view, list view, column view) and on the Desktop. Making the app the default opener can change the icon of every file of that type, which would give it away. Fix this in this order of preference:
   - a. Don't set `CFBundleTypeIconFile` on the document types, and check whether Finder keeps showing the system or Excel document icon.
   - b. If Finder switches to a generic or app-branded icon, try `CFBundleTypeIconSystemGenerated`, and compare what it produces.
   - c. Last resort: at lock time, read the icon the file had before locking (`NSWorkspace.shared.icon(forFile:)`) and set it as a custom icon on the locked file (`NSWorkspace.shared.setIcon(_:forFile:)`). Note: this only covers locked files, so (a) or (b) still needs to keep unlocked files looking normal.
   - Don't copy Microsoft's icon files into the app bundle.
2. **Extension and name:** these are unchanged. "Get Info" shows the same kind (for example "Microsoft Excel workbook").
3. **"Open With" default:** Get Info shows my app as the default opener for the type. That's expected, but note it in the README.
4. **Quick Look (space bar) and the Finder preview pane:** a locked file will fail to preview. Check what macOS shows. If it shows a broken or odd preview, add a Quick Look preview extension that shows an empty document for locked files, and leaves normal files to the system preview.
5. **Double-clicking an unlocked file** opens it in Excel with no visible delay or flash.
6. **Opening a locked file from inside Excel** (File > Open, or Recent files) skips my app and shows Excel's "file is damaged" error. That's acceptable. Note it in the README.

## Also test

- Real password, decoy word, wrong password, empty password, a password with a space at the end.
- Edit and save the real file, close it, reopen it with the real password: the changes are there. Then reopen it with the decoy word: still empty.
- A file of 100 MB or more.
- Lock the same file twice. It should refuse or detect that it's already locked.
- Restart the Mac, then open a locked file.
- No temp copies left behind after closing files (check the temp folder).
- Remove the app and restore the original default apps. Add an "Uninstall" option in settings that unlocks nothing, restores the previous defaults, and warns that locked files will need the app to open.

## Deliverables

- An Xcode project that builds with one command, plus a `README.md` covering install steps, how to set the default opener, known limits, and how to uninstall.
- An install script that builds the app, ad-hoc signs it, copies it to `/Applications`, and registers it with Launch Services (`lsregister -f`).
- A short test checklist that I can run by hand.

## Known limits (state these plainly in the README)

- There's no way to recover a forgotten real password.
- On a Mac without this app, a locked file looks damaged and won't open.
- This protects against someone looking over your shoulder. It won't stop a forensic investigation.
- The app is unsigned (free), so the first launch needs System Settings, then Privacy & Security, then "Open Anyway".

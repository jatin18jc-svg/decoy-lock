# Test checklist

Run `./build.sh --test --large` first. It covers the file format, passwords with spaces, in-place locking, double-lock refusal, the edit-and-save loop, cleanup of temp copies and the 100 MB case, all on scratch files. The checks below need you, Finder and the real apps.

Before you start, make two copies of a real spreadsheet, document, presentation and PDF: lock one of each and leave the other alone. Use copies, not your only originals.

## Setup

- [ ] `./install.sh` builds and opens setup.
- [ ] The demo switches between full sheet, empty sheet and "Incorrect password", and the mascot is happy, playing dead or worried to match.
- [ ] In "Choose your pair", the mascot covers its eyes in the real password fields, peeks when "Show what I'm typing" is on, and plays dead in the decoy field.
- [ ] Mismatched passwords, a real password under 8 characters, and a decoy word equal to the real password are each refused with a clear message.

## Looks like a normal file

Put the locked and unlocked copy of each type side by side in Finder.

- [ ] **Icon**: same in icon view, list view, column view and on the Desktop. Note: in icon view, a normal file may show a content thumbnail while the locked one shows the type's icon. If that bothers you, turn on Settings > Looks > blank-page thumbnail and lock a fresh copy.
- [ ] **Name and extension** unchanged. **Get Info > Kind** reads the same for both (for example "Microsoft Excel Workbook (.xlsx)").
- [ ] **Get Info > Open with** shows Decoy Lock for the locked file only, and the usual app (Excel and so on) for the unlocked one.
- [ ] **Spacebar (Quick Look)** and the Finder preview pane: note what the locked file shows. It should be the type's icon, not an error.
- [ ] **Double-click the unlocked file**: it opens in its usual app with no password box. Decoy Lock isn't involved.
- [ ] **Double-click the locked file**: the password box appears.
- [ ] **Open the locked file from inside Excel** (File > Open or Recent): Excel says the file is damaged. That's expected.

## Passwords

For a locked `.xlsx`:

- [ ] Real password: opens with everything in it.
- [ ] Decoy word: opens empty, same app, same name in the title bar.
- [ ] A wrong password: "Incorrect password", the field shakes, the box stays.
- [ ] An empty password: "Incorrect password".
- [ ] The real password with a space added at the end: "Incorrect password".
- [ ] Real and decoy look the same to someone watching: same box, same pause, same app.

Repeat the real and decoy checks for `.docx`, `.pptx` and `.pdf`. The decoy should open without any "repair" or "damaged" message in Word, PowerPoint and Preview.

## Editing

- [ ] Open with the real password, change something, save, close. Open again with the real password: the change is there.
- [ ] Open again with the decoy word: still empty.
- [ ] Open with the decoy word, type something, save, close. Open with the real password: your real contents, untouched.
- [ ] With the real file open, save twice a minute apart. Both saves stick.
- [ ] Close the file, wait 10 seconds, then run `ls "$TMPDIR/dl"`. It's empty or missing.

## Locking
- [ ] Lock a file you downloaded from the web or email. Double-clicking it shows the password box, not a "could not verify" warning, and Office opens the unlocked copy in Protected View as it would the original.
- [ ] Drop an already-locked file on the menu bar icon: it says it's already locked, and it opens with the password box afterwards.

- [ ] Right-click > Services > Lock with Decoy Lock works on one file and on several.
- [ ] Dropping a file on the menu bar icon opens the lock window.
- [ ] Locking an already-locked file says "is already locked".
- [ ] Locking a file that's open in Excel says to close it first.
- [ ] "Use a different pair" locks with the one-off pair, and the usual pair doesn't open that file.
- [ ] Creation and modification dates (Get Info) are the same before and after locking.

## Big files and restarts

- [ ] Lock a file of 100 MB or more, open it with the real password, save a change, reopen.
- [ ] Restart the Mac, then double-click a locked file. The password box appears and the real password works.
- [ ] After the restart, `ls "$TMPDIR/dl"` shows no leftover copies.

## Sharing

- [ ] `./package.sh` makes `dist/Decoy-Lock-1.0.dmg`.
- [ ] On another Mac: open the disk image, drag the app to Applications, open it, then use Privacy & Security > Open Anyway. Setup appears.
- [ ] Send a locked file to that Mac (AirDrop keeps its per-file setting). Double-clicking it there shows the password box, and your real password opens it.

## Forgotten password

- [ ] Settings > Show Pair asks for Touch ID or your Mac password, then shows your real password and decoy word.
- [ ] Change the pair, then Show Pair again: the old pair is listed under "Earlier pairs", and it still opens a file you locked before the change.
- [ ] Change Pair > "Forgot it?" lets you set a new pair after Touch ID, without typing the current one.

## Uninstall

- [ ] Settings > Uninstall Decoy Lock… shows the warning and quits.
- [ ] The app is in the Trash, the login item is gone, and Keychain Access has no "Decoy Lock" item.
- [ ] A locked file now opens in Excel as "damaged". Reinstall and it opens with the real password again.

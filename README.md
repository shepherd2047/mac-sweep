# MacSweep

A native SwiftUI disk cleaner and space analyzer for macOS.

macOS's storage settings show a huge grey "System Data" / "Other" bar and don't explain it. Apps also keep their data apart from the app: an app in `/Applications` may look like 1 GB while it stores 5 GB more across `~/Library/Containers`, `Application Support`, `Caches` and dot folders. MacSweep shows where every gigabyte goes and helps you remove the parts you don't need.

Everything MacSweep removes goes to the Trash, so you can get it back until you empty it. Git worktrees and Homebrew packages are removed with `git` and `brew` themselves.

## Space analysis

MacSweep scans the whole Data volume (about a minute for about 1.2 million files) and gives every folder to exactly one owner:

- **Apps**: each app's total is the app plus all of its data: sandbox containers, group containers, Application Support, caches, web storage, saved state, logs and its dot folder in your home folder. For example, Xcode = app + `/Library/Developer` + simulator runtimes + developer docs, and VS Code = app + `~/.vscode` + `Application Support/Code`. Data that no installed app owns is listed under its own name.
- **Personal files**: Desktop, Documents, Downloads, Photos, iCloud Drive local copies, iPhone backups, Trash and other folders in your home folder.
- **System data**: resources macOS downloaded for Siri, translation, fonts and Apple Intelligence; temporary files in `/private/var/folders`; swap and sleep image; system databases; data from built-in macOS services (Maps cache, media analysis, …).
- **macOS itself**: the sealed System volume, Preboot, Recovery and VM. These are APFS volumes, read from `diskutil apfs list`.
- **Unreadable**: whatever even Full Disk Access cannot list, such as the Spotlight index, document revisions, fseventsd, APFS snapshots and purgeable space. MacSweep shows this as a number with an explanation, so the bar still adds up.

Click any row to see the exact folders behind it and reveal them in Finder. The **Folders** tab lets you drill down through the disk sorted by size, and shows which app or category each folder belongs to.

## Cleanup categories

| Category | What it finds |
|---|---|
| Caches & logs | `~/Library/Caches`, `~/.cache`, `~/Library/Logs`, npm/pnpm/bun/cargo/go/gradle/NuGet caches, leftover `*.ShipIt` updater downloads |
| Uninstall leftovers | Entries in 11 `~/Library` locations (Application Support, Containers, Group Containers, Caches, Preferences, HTTPStorages, WebKit, Saved Application State, …) that no installed app owns, grouped per app |
| Rarely used apps | Third-party apps in `/Applications` and `~/Applications`, sorted by last use; uninstalling also removes their `~/Library` data |
| Large re-downloadables | macOS aerial wallpaper videos, Claude VM bundles, HuggingFace/Whisper/LM Studio/Ollama models, Docker disks, installers in Downloads |
| Developer junk | Merged and clean git worktrees, old editor extension versions, Xcode DerivedData and friends, Homebrew cache and leaf packages, `node_modules` untouched for 60+ days |

Every item has a risk level:

- **Safe**: gets rebuilt on its own or can be downloaded again.
- **Review**: may hold data or settings you care about.
- **Careful**: possibly still in use, for example written to in the last 14 days.

**How leftovers are detected.** MacSweep gathers every installed bundle ID: all `.app` bundles Spotlight knows about, including Steam games, plus the helpers, extensions and login items nested inside them. It adds command-line tools from PATH and Homebrew. Only `~/Library` entries that match none of these count as leftovers. An entry matched by name rather than by bundle ID, or one that holds user data, is marked *Review*.

## Build

Needs only the Command Line Tools (Swift 6); Xcode is not required. macOS 14 or later.

```bash
./scripts/build-app.sh --install   # build dist/MacSweep.app and copy it to ~/Applications
swift build && .build/debug/MacSweep --dump   # print all cleanup scan results in the terminal
open -n ~/Applications/MacSweep.app --args --space /tmp/space.txt   # write the space analysis to a file
```

## Permissions

- **Full Disk Access.** Without it, MacSweep skips other apps' Containers, the Trash, Downloads and Documents, so macOS doesn't keep showing permission prompts. To grant it, enable MacSweep in *System Settings › Privacy & Security › Full Disk Access*. MacSweep rescans automatically when you switch back to it.
- **Signing.** `scripts/setup-signing.sh` creates a self-signed certificate in a separate keychain (`~/Library/Keychains/macsweep-signing.keychain-db`) and doesn't touch your login keychain. `build-app.sh` signs with that certificate. Because the signing identity stays the same, the permission survives rebuilds. An ad-hoc signature changes with every build, so macOS treats each build as a new app and forgets the grant.
- **Automation (Finder).** Apps installed from the App Store are owned by root, so a normal move to the Trash fails. MacSweep then asks Finder to delete them, which may prompt for your admin password.

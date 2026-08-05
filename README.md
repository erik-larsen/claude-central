# claude-central

One shared NAS store for Claude desktop-app (Mac + Windows) code sessions:
central backup, and access to every session from any machine.

Central store: `\\yournas\YourShare\claude-central` (Mac: `/Volumes/YourShare/claude-central`)

## What a session is

A desktop-app session is **two** pieces; both are needed for it to appear and open:

| Piece | Mac | Windows |
|---|---|---|
| Transcript (`<uuid>.jsonl`) | `~/.claude/projects/<encoded-path>/` | `%USERPROFILE%\.claude\projects\<encoded-path>\` |
| GUI session index (`local_*.json`) | `~/Library/Application Support/Claude/claude-code-sessions/<account>/<org>/` | `%APPDATA%\Claude\claude-code-sessions\<account>\<org>\` |

Both machines use the same account/org UUIDs, and encoded project paths are
OS-specific, so everything merges into one tree with no collisions:

```
claude-central/
├── projects/                 # merged transcripts from all machines
└── claude-code-sessions/     # merged GUI index entries
```

Credentials and settings are per-machine and are deliberately never synced.

## Step 1 — sync scripts

The scripts read the central store location from `shared-path.txt` next to
them (gitignored — copy `shared-path.txt.example` and fill in your paths).
If the file is missing they print instructions and sync nothing.

Mac:

```bash
./sync-claude-central.sh          # push local -> NAS (default)
./sync-claude-central.sh pull     # pull NAS -> local (quit Claude app first)
```

Windows (PowerShell):

```powershell
.\sync-claude-central.ps1          # push local -> NAS (default)
.\sync-claude-central.ps1 pull     # pull NAS -> local (quit Claude app first)
```

Both are additive and newest-wins — nothing is ever deleted from either side.
Run `push` on a machine after working there; run `pull` (with the app fully
quit, including the tray icon on Windows) before working somewhere else.

## Step 2 — pointing the apps at the central store directly

There is no supported setting to relocate these directories (the CLI's
`CLAUDE_CONFIG_DIR` env var doesn't cover the desktop app's AppData index),
so the mechanism is symlinks. Quit the Claude app completely first.

**Mac:**

```bash
mv ~/.claude/projects ~/.claude/projects.local
ln -s /Volumes/YourShare/claude-central/projects ~/.claude/projects
mv "$HOME/Library/Application Support/Claude/claude-code-sessions" \
   "$HOME/Library/Application Support/Claude/claude-code-sessions.local"
ln -s /Volumes/YourShare/claude-central/claude-code-sessions \
   "$HOME/Library/Application Support/Claude/claude-code-sessions"
```

**Windows** (admin prompt, or enable Developer Mode; note `mklink /J`
junctions cannot target network paths — it must be `/D` symlinks):

```cmd
cd /d %USERPROFILE%\.claude
ren projects projects.local
mklink /D projects \\yournas\YourShare\claude-central\projects
cd /d %APPDATA%\Claude
ren claude-code-sessions claude-code-sessions.local
mklink /D claude-code-sessions \\yournas\YourShare\claude-central\claude-code-sessions
```

To undo on either OS: delete the symlink, rename `*.local` back.

### Caveats — read before symlinking

- **One machine at a time.** Two live apps writing the same store over SMB can
  clobber index entries. The apps were never designed for shared storage.
- **The NAS must be mounted before the app launches.** On the Mac, SMB shares
  don't automount at login by default — add `smb://yournas/YourShare` to Login
  Items (System Settings → General → Login Items), or sessions silently fail
  to save into a dangling symlink. If the NAS drops mid-session, writes fail.
- **Transcripts are written continuously during a session.** A NAS hiccup
  mid-write risks a truncated JSONL. This is the real cost of the symlink
  approach versus the sync scripts.
- **Cleanup pruning:** `"cleanupPeriodDays": 9999` must be in
  `~/.claude/settings.json` / `%USERPROFILE%\.claude\settings.json` on **every**
  machine that touches the store, or one machine's startup cleanup prunes
  everyone's old sessions. (Both machines already have it.)
- **Cross-machine resume:** every session appears in the list on every
  machine, but *continuing* one only fully works if its project folder exists
  at the same absolute path on that machine (Windows sessions reference
  `C:\msys64\home\...`, Mac ones `/Users/larsens/...`). Reading is fine
  regardless.

### Recommendation

Prefer the sync scripts (push after working, pull before working elsewhere).
You get the same outcome — all sessions everywhere, centrally backed up — with
local-disk reliability during live sessions, and no NAS-mounted-at-launch or
mid-session-hiccup failure modes. Symlinks are the zero-discipline option; use
them only if the NAS mount is rock solid and you truly use one machine at a time.

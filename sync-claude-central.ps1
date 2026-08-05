# sync-claude-central.ps1 -- sync this PC's Claude desktop-app sessions with the
# central NAS store.
#
#   .\sync-claude-central.ps1              # push: copy local sessions -> NAS (default)
#   .\sync-claude-central.ps1 pull         # pull: copy NAS sessions -> local
#   .\sync-claude-central.ps1 push -Central \\othernas\share\claude-central
#
# The central store location comes from shared-path.txt next to this script
# (the "windows:" line); the -Central parameter overrides it.
#
# A session = transcript JSONL under .claude\projects + index entry under
# claude-code-sessions. Both are synced; nothing else (no credentials, no
# settings) leaves this machine. Copies are additive and newest-wins (/XO):
# nothing is ever deleted from either side.

param(
    [ValidateSet('push', 'pull')]
    [string]$Mode = 'push',
    [string]$Central
)

$ErrorActionPreference = 'Stop'

if (-not $Central) {
    $pathsFile = Join-Path $PSScriptRoot 'shared-path.txt'
    if (-not (Test-Path $pathsFile)) {
        Write-Host 'shared-path.txt not found next to this script - nothing synced.'
        Write-Host 'Create it there with the central store location for each OS, e.g.:'
        Write-Host ''
        Write-Host '  mac: /Volumes/YourShare/claude-central'
        Write-Host '  windows: \\yournas\YourShare\claude-central'
        exit 1
    }
    $line = Get-Content $pathsFile | Where-Object { $_ -match '^\s*windows:' } | Select-Object -First 1
    if (-not $line) {
        Write-Host "error: no 'windows:' line found in $pathsFile - nothing synced."
        exit 1
    }
    $Central = ($line -replace '^\s*windows:\s*', '').Trim()
}

$projects = Join-Path $env:USERPROFILE '.claude\projects'
$sessions = Join-Path $env:APPDATA 'Claude\claude-code-sessions'

if (-not (Test-Path (Split-Path $Central -Parent))) {
    throw "Cannot reach $(Split-Path $Central -Parent) - is the NAS online and the share accessible?"
}

New-Item -ItemType Directory -Force -Path "$Central\projects", "$Central\claude-code-sessions" | Out-Null

function Sync-Tree($label, $src, $dst) {
    if (-not (Test-Path $src)) { Write-Host "skip (missing): $src"; return }
    Write-Host ""
    Write-Host "==> $label"
    Write-Host "    $src  ->  $dst"
    # /E all subdirs, /XO skip older (newest wins), /FFT tolerant timestamps for
    # SMB. Per-file lines print as files copy; the job summary (/NJS removed)
    # shows totals for Copied / Skipped / Bytes at the end of each tree.
    robocopy $src $dst /E /XO /FFT /R:2 /W:2 /NP /NDL /NJH
    if ($LASTEXITCODE -ge 8) { throw "robocopy failed (exit $LASTEXITCODE): $src -> $dst" }
}

if ($Mode -eq 'push') {
    Write-Host "Pushing local sessions -> $Central"
    Sync-Tree 'transcripts (.claude\projects)' $projects "$Central\projects"
    Sync-Tree 'session index (claude-code-sessions)' $sessions "$Central\claude-code-sessions"
} else {
    Write-Host "Pulling $Central -> local sessions"
    Write-Host "(quit Claude for Windows first, including the system tray icon)"
    Sync-Tree 'transcripts (.claude\projects)' "$Central\projects" $projects
    Sync-Tree 'session index (claude-code-sessions)' "$Central\claude-code-sessions" $sessions
}

$t = (Get-ChildItem "$Central\projects" -Recurse -Filter *.jsonl -ErrorAction SilentlyContinue).Count
$i = (Get-ChildItem "$Central\claude-code-sessions" -Recurse -Filter local_*.json -ErrorAction SilentlyContinue).Count
Write-Host "Done. Central store now has: $t transcripts, $i index entries"

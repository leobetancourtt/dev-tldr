# dev-tldr installer (Windows PowerShell)
#   .\install.ps1          -> copy the skill to ~\.claude\skills\dev-tldr (Claude Code)
#   .\install.ps1 -Zip     -> build dist\dev-tldr.zip (Claude Desktop upload)
#   .\install.ps1 -Config  -> also create ~\.claude\dev-tldr.config.md if missing
param([switch]$Zip, [switch]$Config)

$ErrorActionPreference = "Stop"
$src = Join-Path $PSScriptRoot "skills\dev-tldr"

if (-not (Test-Path (Join-Path $src "SKILL.md"))) {
    Write-Host "ERROR: $src\SKILL.md not found. Run from the repo root." -ForegroundColor Red
    exit 1
}

if ($Zip) {
    $dist = Join-Path $PSScriptRoot "dist"
    New-Item -ItemType Directory -Force -Path $dist | Out-Null
    $zipPath = Join-Path $dist "dev-tldr.zip"
    if (Test-Path $zipPath) { Remove-Item $zipPath -Force }
    # The zip must contain ONE top-level folder named dev-tldr with SKILL.md inside.
    Compress-Archive -Path $src -DestinationPath $zipPath
    Write-Host "Built: $zipPath" -ForegroundColor Green
    Write-Host "Next: Claude Desktop > Settings > Capabilities > Skills > Upload skill."
    exit 0
}

$skillsDir = Join-Path $env:USERPROFILE ".claude\skills"
$dest = Join-Path $skillsDir "dev-tldr"
New-Item -ItemType Directory -Force -Path $skillsDir | Out-Null

if (Test-Path $dest) {
    $confirm = Read-Host "Found existing $dest. Overwrite? (y/n)"
    if ($confirm -ne "y") { Write-Host "Cancelled."; exit 0 }
    Remove-Item $dest -Recurse -Force
}
Copy-Item -Path $src -Destination $dest -Recurse -Force
Write-Host "Installed skill to $dest" -ForegroundColor Green

if ($Config) {
    $cfg = Join-Path $env:USERPROFILE ".claude\dev-tldr.config.md"
    if (Test-Path $cfg) {
        Write-Host "Config already exists at $cfg (left untouched)."
    } else {
        Copy-Item (Join-Path $src "references\config.example.md") $cfg
        Write-Host "Created $cfg - edit it with your Jira/Confluence/GitHub/Slack scope." -ForegroundColor Green
    }
}

Write-Host ""
Write-Host "Next: connect Atlassian, Slack and GitHub (see README), then run: tldr PROJ-123"

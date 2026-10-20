# dev-tldr installer (Windows PowerShell) - interactive wizard.
#   .\install.ps1            Interactive setup (skill + config + connectors)
#   .\install.ps1 -Yes       Non-interactive; values come from env vars
#   .\install.ps1 -Doctor    Check the current setup, change nothing
#   .\install.ps1 -Zip       Only build dist\dev-tldr.zip (Claude Desktop upload)
#
# Env vars (defaults / -Yes mode): TARGET=code|desktop|both JIRA_DOMAIN JIRA_PROJECTS
#   CONFLUENCE_SPACES GITHUB_ORG GITHUB_REPOS SLACK_CHANNELS OUTPUT_DIR
#   GITHUB_TOKEN_SOURCE=gh|paste|skip  GITHUB_PAT
param([switch]$Yes, [switch]$Doctor, [switch]$Zip)

$ErrorActionPreference = "Continue"
$Src  = Join-Path $PSScriptRoot "skills\dev-tldr"
$Dest = Join-Path $env:USERPROFILE ".claude\skills\dev-tldr"
$Cfg  = Join-Path $env:USERPROFILE ".claude\dev-tldr.config.md"
$DesktopCfg = Join-Path $env:APPDATA "Claude\claude_desktop_config.json"

function Ok($m)   { Write-Host "  [ok] $m" -ForegroundColor Green }
function Warn($m) { Write-Host "  [!]  $m" -ForegroundColor Yellow }
function Bad($m)  { Write-Host "  [x]  $m" -ForegroundColor Red }
function Step($m) { Write-Host ""; Write-Host $m -ForegroundColor Cyan }
function Have($n) { [bool](Get-Command $n -ErrorAction SilentlyContinue) }
function EnvOr($n) { $v = [Environment]::GetEnvironmentVariable($n); if ($v) { $v } else { "" } }

function Ask($prompt, $default = "") {
    if ($Yes) { return $default }
    $suffix = if ($default) { " [$default]" } else { "" }
    $a = Read-Host "  $prompt$suffix"
    if ($a) { $a } else { $default }
}
function Confirm($q, $def = "y") {
    if ($Yes) { return ($def -eq "y") }
    $hint = if ($def -eq "y") { "Y/n" } else { "y/N" }
    $a = Read-Host "  $q [$hint]"
    if (-not $a) { $a = $def }
    return ($a -eq "y" -or $a -eq "Y")
}
function McpHas($name) {
    if (-not (Have "claude")) { return $false }
    $out = (& claude mcp list 2>$null) -join "`n"
    return ($out -match "(?i)$name")
}
function Build-Zip {
    $dist = Join-Path $PSScriptRoot "dist"
    New-Item -ItemType Directory -Force -Path $dist | Out-Null
    $z = Join-Path $dist "dev-tldr.zip"
    if (Test-Path $z) { Remove-Item $z -Force }
    # One top-level folder named dev-tldr with SKILL.md inside.
    Compress-Archive -Path $Src -DestinationPath $z
    Ok "Built $z"
}
function Run-Doctor {
    Step "dev-tldr doctor"
    if (Test-Path (Join-Path $Dest "SKILL.md")) { Ok "Skill installed: $Dest" } else { Warn "Skill not installed for Claude Code" }
    if (Test-Path $Cfg) { Ok "Config: $Cfg" } else { Warn "No config (optional): $Cfg" }
    if (Have "claude") {
        Ok "claude CLI found"
        $list = (& claude mcp list 2>$null)
        foreach ($s in "atlassian", "slack", "github") {
            $line = $list | Where-Object { $_ -match "(?i)$s" } | Select-Object -First 1
            if (-not $line) { Bad "${s}: not configured" }
            elseif ($line -match "(?i)connected") { Ok $line }
            elseif ($s -eq "github") { Warn "$line (check the token: expired or missing SSO authorization?)" }
            else { Warn "$line (run /mcp inside Claude Code to log in)" }
        }
    } else { Warn "claude CLI not found (fine if you only use Claude Desktop)" }
    if (Have "gh") {
        & gh auth status *> $null
        if ($LASTEXITCODE -eq 0) { Ok "gh logged in" } else { Warn "gh installed but not logged in (gh auth login)" }
    } else { Warn "gh not installed (optional fallback)" }
    Write-Host ""
    Write-Host "  Logins (Atlassian, Slack) are completed in Claude: /mcp (Code) or Settings > Connectors (Desktop)."
}

if (-not (Test-Path (Join-Path $Src "SKILL.md"))) { Bad "$Src\SKILL.md not found. Run from the repo root."; exit 1 }
if ($Zip)    { Build-Zip; exit 0 }
if ($Doctor) { Run-Doctor; exit 0 }

# ---------------------------------------------------------------- wizard
Step "1/6  Prerequisites"
if (Have "claude") { Ok "claude CLI" } else { Warn "claude CLI not found (Claude Code option unavailable)" }
if (Have "gh")     { Ok "gh CLI" } else { Warn "gh CLI not found (optional)" }
if (Have "docker") { Ok "docker" } else { Warn "docker not found (needed only for GitHub on Claude Desktop)" }

Step "2/6  Where do you use Claude?"
$target = EnvOr "TARGET"
if (-not $target) {
    Write-Host "    1) Claude Code   2) Claude Desktop   3) Both"
    $def = if (Have "claude") { "1" } else { "2" }
    switch (Ask "Choose" $def) { "1" { $target = "code" } "2" { $target = "desktop" } "3" { $target = "both" } default { $target = "code" } }
}
$doCode    = ($target -eq "code" -or $target -eq "both")
$doDesktop = ($target -eq "desktop" -or $target -eq "both")
if ($doCode -and -not (Have "claude")) { Bad "Claude Code selected but 'claude' CLI is missing. Install it first."; $doCode = $false }
Ok "Target: $target"

Step "3/6  Scope (press Enter to skip any)"
Write-Host "    Used to focus searches. Nothing here is a secret."
$jiraDomain = Ask "Jira/Confluence domain (e.g. yourorg.atlassian.net)" (EnvOr "JIRA_DOMAIN")
$jiraDomain = ($jiraDomain -replace "^https://", "") -replace "/.*$", ""
if ($jiraDomain) {
    try { Invoke-WebRequest -UseBasicParsing -TimeoutSec 6 "https://$jiraDomain/_edge/tenant_info" | Out-Null; Ok "$jiraDomain is reachable" }
    catch { Warn "Could not verify $jiraDomain (typo, VPN, or offline). Continuing." }
}
$jiraProjects = Ask "Jira project keys, comma-separated (e.g. PAY,BEN)" (EnvOr "JIRA_PROJECTS")
$confSpaces   = Ask "Confluence space keys (e.g. ENG,PAY)" (EnvOr "CONFLUENCE_SPACES")
$ghOrg        = Ask "GitHub org or user (e.g. your-org)" (EnvOr "GITHUB_ORG")
$ghRepos      = Ask "GitHub repos, comma-separated" (EnvOr "GITHUB_REPOS")
$slackCh      = Ask "Slack channels, comma-separated, no # (e.g. eng-payments)" (EnvOr "SLACK_CHANNELS")
$outDefault   = if (EnvOr "OUTPUT_DIR") { EnvOr "OUTPUT_DIR" } else { Join-Path $env:USERPROFILE "dev-tldrs" }
$outDir       = Ask "Where to save tldr-*.md files" $outDefault

New-Item -ItemType Directory -Force -Path (Split-Path $Cfg) | Out-Null
if ((Test-Path $Cfg) -and -not (Confirm "Config exists at $Cfg. Overwrite?" "n")) { Warn "Kept existing config" }
else {
    $lines = @("# dev-tldr config (generated by install.ps1 on $(Get-Date -Format yyyy-MM-dd))", "", '```')
    if ($jiraDomain)   { $lines += "JIRA_DOMAIN: $jiraDomain" }
    if ($jiraProjects) { $lines += "JIRA_PROJECTS: $jiraProjects" }
    if ($confSpaces)   { $lines += "CONFLUENCE_SPACES: $confSpaces" }
    if ($ghOrg)        { $lines += "GITHUB_ORG: $ghOrg" }
    if ($ghRepos)      { $lines += "GITHUB_REPOS: $ghRepos" }
    if ($slackCh)      { $lines += "SLACK_CHANNELS: $slackCh" }
    if ($outDir)       { $lines += "OUTPUT_DIR: $outDir" }
    $lines += '```'
    Set-Content -Path $Cfg -Value $lines -Encoding UTF8
    Ok "Wrote $Cfg"
}
if ($outDir) { New-Item -ItemType Directory -Force -Path $outDir -ErrorAction SilentlyContinue | Out-Null }

Step "4/6  GitHub credential"
$src = EnvOr "GITHUB_TOKEN_SOURCE"
$ghLoggedIn = $false
if (Have "gh") { & gh auth status *> $null; $ghLoggedIn = ($LASTEXITCODE -eq 0) }
if (-not $src) {
    if ($ghLoggedIn) {
        Write-Host "    1) Use my current 'gh' login (fast; token has broad scopes incl. write)"
        Write-Host "    2) Paste a fine-grained read-only token (safer)"
        Write-Host "    3) Skip GitHub"
        $c = Ask "Choose" "1"
    } else {
        Write-Host "    'gh' is not logged in. You can run 'gh auth login' later."
        Write-Host "    2) Paste a fine-grained read-only token (https://github.com/settings/personal-access-tokens/new)"
        Write-Host "    3) Skip GitHub"
        $c = Ask "Choose" "3"
    }
    switch ($c) { "1" { $src = "gh" } "2" { $src = "paste" } default { $src = "skip" } }
}
$token = ""
switch ($src) {
    "gh"    { $token = (& gh auth token 2>$null); if ($token) { Ok "Using token from gh" } else { Bad "gh returned no token" } }
    "paste" {
        $token = EnvOr "GITHUB_PAT"
        if (-not $token -and -not $Yes) {
            $sec = Read-Host "  Paste token (hidden)" -AsSecureString
            $token = [Runtime.InteropServices.Marshal]::PtrToStringAuto([Runtime.InteropServices.Marshal]::SecureStringToBSTR($sec))
        }
        if ($token) { Ok "Token received" } else { Bad "No token given" }
    }
    default { Warn "GitHub skipped. Coverage will show GitHub unavailable." }
}
if ($token) {
    try {
        Invoke-RestMethod -TimeoutSec 8 -Headers @{ Authorization = "Bearer $token" } "https://api.github.com/user" | Out-Null
        Ok "Token accepted by GitHub"
    } catch { Warn "GitHub rejected or could not check this token (expired, or needs SSO authorization)" }
}

Step "5/6  Claude Code"
if ($doCode) {
    New-Item -ItemType Directory -Force -Path (Join-Path $env:USERPROFILE ".claude\skills") | Out-Null
    if (Test-Path $Dest) { Remove-Item $Dest -Recurse -Force }
    Copy-Item -Path $Src -Destination $Dest -Recurse -Force
    Ok "Skill installed: $Dest"

    if (McpHas "atlassian") { Ok "Atlassian already connected (skipped)" }
    elseif (Confirm "Add Atlassian (Jira + Confluence) MCP server?" "y") {
        $aauth = EnvOr "ATLASSIAN_AUTH"
        if (-not $aauth) {
            Write-Host "    1) Browser login (OAuth) - default"
            Write-Host "    2) API token, no browser (your Atlassian admin must enable this for the org)"
            $aauth = if ((Ask "Choose" "1") -eq "2") { "token" } else { "oauth" }
        }
        if ($aauth -eq "token") {
            Write-Host "    Create a token: https://id.atlassian.com/manage-profile/security/api-tokens"
            $aemail = Ask "Atlassian account email" (EnvOr "ATLASSIAN_EMAIL")
            $atok = EnvOr "ATLASSIAN_API_TOKEN"
            if (-not $atok -and -not $Yes) {
                $sec = Read-Host "  Paste API token (hidden)" -AsSecureString
                $atok = [Runtime.InteropServices.Marshal]::PtrToStringAuto([Runtime.InteropServices.Marshal]::SecureStringToBSTR($sec))
            }
            if (-not $aemail -or -not $atok) { Bad "Email and token are required for token auth. Skipped." }
            else {
                $b64 = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes("${aemail}:${atok}"))
                if ($jiraDomain) {
                    try { Invoke-RestMethod -TimeoutSec 8 -Headers @{ Authorization = "Basic $b64" } "https://$jiraDomain/rest/api/3/myself" | Out-Null; Ok "Token accepted by $jiraDomain" }
                    catch { Warn "Could not verify the token against $jiraDomain. Scoped tokens can still work with MCP; continuing." }
                }
                & claude mcp add --transport http --scope user atlassian https://mcp.atlassian.com/v2/mcp -H "Authorization: Basic $b64" *> $null
                if ($LASTEXITCODE -eq 0) { Ok "Atlassian added with API token (no login needed)" } else { Bad "Could not add Atlassian. If your admin hasn't enabled API-token auth, re-run and choose browser login." }
            }
        } else {
            & claude mcp add --transport http --scope user atlassian https://mcp.atlassian.com/v1/mcp/authv2 *> $null
            if ($LASTEXITCODE -eq 0) { Ok "Atlassian added (login pending)" } else { Bad "Could not add Atlassian. Run: claude mcp add --transport http atlassian https://mcp.atlassian.com/v1/mcp/authv2" }
        }
    }
    if (McpHas "slack") { Ok "Slack already connected (skipped)" }
    elseif (Confirm "Add Slack MCP server? (your workspace admin must approve it)" "y") {
        & claude mcp add --transport http --scope user slack https://mcp.slack.com/mcp *> $null
        if ($LASTEXITCODE -eq 0) { Ok "Slack added (login pending)" } else { Bad "Could not add Slack. Alternative inside Claude Code: /plugin install slack@claude-plugins-official" }
    }
    if ($token) {
        if (McpHas "github") { Ok "GitHub already configured (skipped)" }
        else {
            # Legacy form first: on Windows, add-json can fail with 'Invalid input' for HTTP servers.
            & claude mcp add github --transport http https://api.githubcopilot.com/mcp -H "Authorization: Bearer $token" *> $null
            if ($LASTEXITCODE -eq 0) { Ok "GitHub added" } else { Bad "Could not add GitHub. See README section 3." }
        }
    }
} else { Warn "Skipped (Claude Code not selected or not installed)" }

Step "6/6  Claude Desktop"
if ($doDesktop) {
    Build-Zip
    Write-Host "    Upload it: Settings > Capabilities > Skills > Upload skill  (file: dist\dev-tldr.zip)"
    if ($token) {
        if (-not (Have "docker")) { Warn "GitHub on Desktop needs Docker (not found). Install Docker Desktop, then re-run." }
        elseif ($PSVersionTable.PSVersion.Major -lt 7) { Warn "Editing the Desktop config needs PowerShell 7+ (pwsh). Add the GitHub server by hand (README section 3)." }
        elseif (Confirm "Add GitHub (Docker) server to Claude Desktop config? A backup is made." "y") {
            New-Item -ItemType Directory -Force -Path (Split-Path $DesktopCfg) | Out-Null
            try {
                $cfg = [ordered]@{}
                if ((Test-Path $DesktopCfg) -and (Get-Item $DesktopCfg).Length -gt 0) {
                    Copy-Item $DesktopCfg "$DesktopCfg.bak.$([int](Get-Date -UFormat %s))"
                    $cfg = Get-Content $DesktopCfg -Raw | ConvertFrom-Json -AsHashtable
                }
                if (-not $cfg.ContainsKey("mcpServers")) { $cfg["mcpServers"] = @{} }
                $cfg["mcpServers"]["github"] = @{
                    command = "docker"
                    args = @("run", "-i", "--rm", "-e", "GITHUB_PERSONAL_ACCESS_TOKEN", "ghcr.io/github/github-mcp-server")
                    env = @{ GITHUB_PERSONAL_ACCESS_TOKEN = $token }
                }
                $cfg | ConvertTo-Json -Depth 10 | Set-Content $DesktopCfg -Encoding UTF8
                Ok "GitHub server written to Desktop config (restart Claude Desktop)"
            } catch { Bad "Could not edit $DesktopCfg ($($_.Exception.Message)). Backup kept; add it by hand." }
        }
    }
    Write-Host ""
    Write-Host "    Manual steps in Claude Desktop (no API for these):"
    Write-Host "      - Settings > Connectors > Atlassian > Connect  (or custom connector: https://mcp.atlassian.com/v1/mcp/authv2)"
    Write-Host "      - Settings > Connectors > Slack > Connect"
    Write-Host "      - Restart Claude Desktop, make sure the dev-tldr skill is toggled on"
} else { Warn "Skipped (Claude Desktop not selected)" }

Run-Doctor
Write-Host ""
Write-Host "Almost done. Remaining manual logins:" -ForegroundColor Cyan
if ($doCode)    { Write-Host "  Claude Code: start 'claude', run /mcp, and log in to each server marked 'Needs authentication' (Slack always; Atlassian unless you used an API token)." }
if ($doDesktop) { Write-Host "  Claude Desktop: connect Atlassian and Slack under Settings > Connectors." }
Write-Host "  Then try:  tldr <a-ticket-key-you-know>"
Write-Host "  Re-check any time with: .\install.ps1 -Doctor"

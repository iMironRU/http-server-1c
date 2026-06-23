<#
.SYNOPSIS
    Локальная сборка cfe + публикация GitHub Release.

.DESCRIPTION
    Берёт src/cfe, собирает .cfe через 1cv8 DESIGNER на временной ИБ с
    загруженной УТ-конфигурацией, создаёт git-тег и пушит, потом
    публикует Release с прикреплённым .cfe.

.PARAMETER Version
    Версия релиза (формат семвер: 1.2.3). Тег будет 'v1.2.3'.

.PARAMETER BaseUT
    Путь к УТ-базе (с уже загруженной нужной версией конфигурации).
    Используется как source-of-truth для UUID объектов при сборке cfe.

.PARAMETER Notes
    Текст release notes (Markdown). Если не задан — берётся из CHANGELOG.md
    или генерируется из последних коммитов.

.PARAMETER Draft
    Создать как черновик (не публиковать сразу).

.EXAMPLE
    .\tools\release.ps1 -Version "0.2.0" -BaseUT "C:\Bases\dev_bsp"

.EXAMPLE
    .\tools\release.ps1 -Version "0.2.1-rc1" -BaseUT "C:\Bases\dev_bsp" -Draft
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)] [string]$Version,
    [Parameter(Mandatory)] [string]$BaseUT,
    [string]$Notes = "",
    [switch]$Draft,
    [string]$Platform,
    [string]$ExtensionName = "http_HTTPСервер",
    [string]$RepoRoot = (Split-Path -Parent $PSScriptRoot)
)

$ErrorActionPreference = "Stop"
Set-Location $RepoRoot

function Write-Step($msg) { Write-Host "▶ $msg" -ForegroundColor Cyan }
function Write-OK($msg)   { Write-Host "  ✓ $msg" -ForegroundColor Green }
function Write-Err($msg)  { Write-Host "  ✗ $msg" -ForegroundColor Red }

# 1. Платформа
if (-not $Platform) {
    $candidates = Get-ChildItem "C:\Program Files\1cv8" -Directory -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -match "^8\.3\." } |
        Sort-Object { [Version]$_.Name } -Descending |
        Select-Object -First 1
    if ($candidates) { $Platform = Join-Path $candidates.FullName "bin\1cv8.exe" }
}
if (-not (Test-Path $Platform)) { throw "1cv8.exe не найден; передай -Platform" }
Write-OK "Платформа: $Platform"

# 2. Git: чистая working copy?
$st = git status --porcelain
if ($st) {
    Write-Err "В рабочей копии есть незакоммиченные изменения:"
    Write-Host $st
    throw "Зафиксируй или отложи изменения и повтори"
}
Write-OK "git clean"

# 3. Проставляем версию в src/cfe/Configuration.xml
$cfgPath = Join-Path $RepoRoot "src\cfe\Configuration.xml"
$cfg = Get-Content $cfgPath -Raw -Encoding UTF8
if ($cfg -match "<Version>([^<]+)</Version>") {
    $oldVersion = $matches[1]
    $cfg = $cfg -replace "<Version>[^<]+</Version>", "<Version>$Version</Version>"
    Set-Content -Path $cfgPath -Value $cfg -Encoding UTF8 -NoNewline
    Write-OK "Version: $oldVersion → $Version"
} else {
    Write-Err "В Configuration.xml не найден <Version>"
    throw "fail"
}

# 4. Загружаем XML в УТ-базу + UpdateDBCfg
Write-Step "LoadConfigFromFiles"
$logL = [System.IO.Path]::GetTempFileName()
$srcCfe = Join-Path $RepoRoot "src\cfe"
$argsL = @("DESIGNER", "/F`"$BaseUT`"",
    "/LoadConfigFromFiles", "`"$srcCfe`"", "-Extension", "`"$ExtensionName`"",
    "/UpdateDBCfg", "/DisableStartupDialogs", "/Out`"$logL`"")
$p = Start-Process $Platform -ArgumentList $argsL -Wait -PassThru -NoNewWindow
if ($p.ExitCode -ne 0) {
    Write-Err "LoadConfigFromFiles упал ($($p.ExitCode))"
    Get-Content $logL | Write-Host
    throw "fail"
}
Write-OK "загружено в УТ-базу"

# 5. DumpCfg
Write-Step "DumpCfg"
$outCfe = Join-Path $RepoRoot "build\http_HTTPСервер-$Version.cfe"
New-Item -ItemType Directory -Force -Path (Split-Path $outCfe) | Out-Null
$logD = [System.IO.Path]::GetTempFileName()
$argsD = @("DESIGNER", "/F`"$BaseUT`"",
    "/DumpCfg", "`"$outCfe`"", "-Extension", "`"$ExtensionName`"",
    "/DisableStartupDialogs", "/Out`"$logD`"")
$p = Start-Process $Platform -ArgumentList $argsD -Wait -PassThru -NoNewWindow
if ($p.ExitCode -ne 0) { Get-Content $logD | Write-Host; throw "DumpCfg fail" }
$size = [Math]::Round((Get-Item $outCfe).Length / 1KB)
Write-OK "$outCfe ($size КБ)"

# 6. Git commit + tag
Write-Step "git commit + tag"
git add $cfgPath | Out-Null
git commit -m "release: $Version" | Out-Null
git tag "v$Version" -m "Release $Version"
git push origin HEAD
git push origin "v$Version"
Write-OK "тег v$Version запушен"

# 7. Release notes
if (-not $Notes) {
    $changelog = Join-Path $RepoRoot "CHANGELOG.md"
    if (Test-Path $changelog) {
        # Извлекаем секцию для этой версии (## v0.2.0 или ## 0.2.0)
        $cl = Get-Content $changelog -Raw -Encoding UTF8
        $rx = "(?ms)##\s*v?$([regex]::Escape($Version))\b.*?(?=^##\s|\z)"
        if ($cl -match $rx) { $Notes = $matches[0] }
    }
    if (-not $Notes) {
        # Фолбэк — последние коммиты
        $Notes = "## Изменения`n`n" + (git log "v$Version~1..v$Version" --oneline 2>$null | ForEach-Object { "- $_" }) -join "`n"
    }
}

# 8. GitHub Release
Write-Step "gh release create"
$ghArgs = @("release", "create", "v$Version", $outCfe,
    "--title", "v$Version",
    "--notes", $Notes)
if ($Draft) { $ghArgs += "--draft" }
& gh @ghArgs
if ($LASTEXITCODE -ne 0) { throw "gh release create fail" }
Write-OK "Release опубликован: v$Version"

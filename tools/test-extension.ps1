<#
.SYNOPSIS
    Дымовой тест расширения http_HTTPСервер на Windows.

.DESCRIPTION
    Автоматизирует полный цикл проверки расширения для УТ:
      install — установка cfe в файловую ИБ
      verify  — выгрузка XML после установки и проверка наличия ключевых объектов
      remove  — удаление расширения из ИБ
      http    — curl-тесты эндпоинтов /http/ping, /jrpc/call, /swagger/swagger.json
                (требует опубликованной базы на веб-сервере)
      all     — install + verify + http (если задан -BaseURL)

.PARAMETER Action
    install | verify | remove | http | all (default: all)

.PARAMETER CfeFile
    Путь к http_HTTPСервер.cfe.
    По умолчанию ищется на Desktop текущего пользователя.

.PARAMETER BasePath
    Каталог файловой ИБ. Обязателен для install/verify/remove.

.PARAMETER Server
    Сервер 1С (для серверной ИБ; альтернатива -BasePath).

.PARAMETER InfoBase
    Имя ИБ на сервере (вместе с -Server).

.PARAMETER User
    Пользователь ИБ (Администратор по умолчанию).

.PARAMETER Password
    Пароль пользователя.

.PARAMETER Platform
    Путь к 1cv8.exe.
    По умолчанию автоопределение по C:\Program Files\1cv8\ — берётся самая свежая 8.3.27.

.PARAMETER BaseURL
    URL опубликованной базы (например http://localhost/MyBase).
    Нужен только для action=http или all.

.EXAMPLE
    # Установить и проверить
    .\test-extension.ps1 -BasePath "C:\Bases\MyUT"

.EXAMPLE
    # Только удалить из ИБ
    .\test-extension.ps1 -BasePath "C:\Bases\MyUT" -Action remove

.EXAMPLE
    # Полный цикл с HTTP-тестами
    .\test-extension.ps1 -BasePath "C:\Bases\MyUT" -BaseURL "http://localhost/MyUT" -Action all
#>

[CmdletBinding()]
param(
    [ValidateSet("install","verify","remove","http","all")]
    [string]$Action = "all",

    [string]$CfeFile = "$env:USERPROFILE\Desktop\http_HTTPСервер.cfe",
    [string]$BasePath,
    [string]$Server,
    [string]$InfoBase,
    [string]$User = "Администратор",
    [string]$Password = "",
    [string]$Platform,
    [string]$BaseURL,
    [string]$ExtensionName = "http_HTTPСервер"
)

$ErrorActionPreference = "Stop"

# ---------- Утилиты ----------

function Write-Header($text) {
    Write-Host ""
    Write-Host ("=" * 70) -ForegroundColor Cyan
    Write-Host $text -ForegroundColor Cyan
    Write-Host ("=" * 70) -ForegroundColor Cyan
}

function Write-OK($text)    { Write-Host "  [OK] $text" -ForegroundColor Green }
function Write-Fail($text)  { Write-Host "  [!!] $text" -ForegroundColor Red }
function Write-Info($text)  { Write-Host "  [..] $text" -ForegroundColor Gray }

function Resolve-Platform {
    if ($Platform -and (Test-Path $Platform)) { return $Platform }

    # Автоопределение последней установленной 8.3.27.*
    $bases = @(
        "C:\Program Files\1cv8",
        "C:\Program Files (x86)\1cv8"
    )
    foreach ($base in $bases) {
        if (-not (Test-Path $base)) { continue }
        $candidate = Get-ChildItem $base -Directory |
            Where-Object { $_.Name -match "^8\.3\.\d+\.\d+$" } |
            Sort-Object { [Version]$_.Name } -Descending |
            Select-Object -First 1
        if ($candidate) {
            $exe = Join-Path $candidate.FullName "bin\1cv8.exe"
            if (Test-Path $exe) { return $exe }
        }
    }
    throw "Не найден 1cv8.exe. Укажите путь параметром -Platform"
}

function Get-ConnString {
    if ($BasePath)               { return "/F`"$BasePath`"" }
    if ($Server -and $InfoBase)  { return "/S`"$Server\$InfoBase`"" }
    throw "Не задан путь к ИБ. Используйте -BasePath или -Server + -InfoBase"
}

function Get-AuthArgs {
    $args = @()
    if ($User)     { $args += "/N`"$User`"" }
    if ($Password) { $args += "/P`"$Password`"" }
    return $args
}

function Invoke-Designer {
    param([string[]]$Args, [string]$LogPath)

    if (-not $LogPath) {
        $LogPath = [System.IO.Path]::GetTempFileName()
    }

    $allArgs = @("DESIGNER", (Get-ConnString)) + (Get-AuthArgs) + $Args + @(
        "/DisableStartupDialogs",
        "/Out`"$LogPath`""
    )

    $platformExe = Resolve-Platform
    Write-Info "→ $platformExe $($allArgs -join ' ')"

    $proc = Start-Process -FilePath $platformExe -ArgumentList $allArgs -Wait -PassThru -NoNewWindow
    $log = if (Test-Path $LogPath) { Get-Content $LogPath -Raw -Encoding UTF8 } else { "" }

    return [PSCustomObject]@{
        ExitCode = $proc.ExitCode
        Log      = $log
        LogPath  = $LogPath
    }
}

# ---------- Действия ----------

function Action-Install {
    Write-Header "Установка расширения"

    if (-not (Test-Path $CfeFile)) {
        Write-Fail "Файл расширения не найден: $CfeFile"
        return $false
    }
    Write-OK "Файл найден: $CfeFile ($([Math]::Round((Get-Item $CfeFile).Length / 1KB)) КБ)"

    # Удаляем старое расширение если есть (через LoadCfg того же имени с /UpdateDBCfg)
    # — но проще полагаться на /LoadCfg с -Extension: оно заменит существующее
    $result = Invoke-Designer @(
        "/LoadCfg", "`"$CfeFile`"",
        "-Extension", "`"$ExtensionName`"",
        "/UpdateDBCfg"
    )

    if ($result.ExitCode -ne 0) {
        Write-Fail "Установка завершилась с кодом $($result.ExitCode)"
        Write-Host $result.Log
        return $false
    }

    if ($result.Log -match "Загрузка конфигурации успешно завершена") {
        Write-OK "Расширение загружено"
    } else {
        Write-Fail "В логе нет подтверждения загрузки:"
        Write-Host $result.Log
        return $false
    }

    return $true
}

function Action-Verify {
    Write-Header "Проверка установки"

    $tmpDump = Join-Path $env:TEMP "http_ext_verify_$([Guid]::NewGuid().ToString('N'))"
    New-Item -ItemType Directory -Path $tmpDump -Force | Out-Null

    $result = Invoke-Designer @(
        "/DumpConfigToFiles", "`"$tmpDump`"",
        "-Extension", "`"$ExtensionName`""
    )

    if ($result.ExitCode -ne 0) {
        Write-Fail "Не удалось выгрузить расширение: $($result.ExitCode)"
        Write-Host $result.Log
        Remove-Item $tmpDump -Recurse -Force -ErrorAction SilentlyContinue
        return $false
    }

    # Ожидаемые объекты
    $expected = @{
        "Configuration.xml"                                          = "Корневая конфигурация"
        "Languages\Русский.xml"                                       = "Язык Русский"
        "CommonModules\http_HTTPКонвейер\Ext\Module.bsl"              = "Модуль HTTPКонвейер"
        "CommonModules\http_JRPCСервер\Ext\Module.bsl"                = "Модуль JRPC сервер"
        "CommonModules\http_АутентификацияСлужебный\Ext\Module.bsl"   = "Модуль аутентификации"
        "CommonModules\http_SwaggerГенератор\Ext\Module.bsl"          = "Модуль Swagger генератор"
        "Catalogs\http_APIКлючи.xml"                                  = "Справочник API ключей"
        "Catalogs\http_HTTPСервисы.xml"                               = "Справочник настроек сервисов"
        "InformationRegisters\http_ЖурналВходящихЗапросов.xml"        = "Регистр журнала"
        "HTTPServices\http_Ping.xml"                                  = "HTTP-сервис Ping"
        "HTTPServices\http_JRPC.xml"                                  = "HTTP-сервис JRPC"
        "HTTPServices\http_Swagger.xml"                               = "HTTP-сервис Swagger"
        "ScheduledJobs\http_РазблокировкаКонфликтов.xml"              = "РЗ Разблокировка"
        "ScheduledJobs\http_СокращениеЖурналов.xml"                   = "РЗ Сокращение"
    }

    $missing = 0
    foreach ($path in $expected.Keys) {
        $full = Join-Path $tmpDump $path
        if (Test-Path $full) {
            Write-OK "$($expected[$path])"
        } else {
            Write-Fail "Не найден: $($expected[$path]) ($path)"
            $missing++
        }
    }

    Remove-Item $tmpDump -Recurse -Force -ErrorAction SilentlyContinue

    if ($missing -gt 0) {
        Write-Fail "Отсутствует объектов: $missing"
        return $false
    }
    Write-OK "Все объекты на месте"
    return $true
}

function Action-Remove {
    Write-Header "Удаление расширения"

    $result = Invoke-Designer @(
        "/DeleteCfg",
        "-Extension", "`"$ExtensionName`"",
        "/UpdateDBCfg"
    )

    if ($result.ExitCode -ne 0) {
        Write-Fail "Удаление завершилось с кодом $($result.ExitCode):"
        Write-Host $result.Log
        return $false
    }
    Write-OK "Расширение удалено"
    return $true
}

function Test-HttpEndpoint {
    param(
        [string]$Url,
        [string]$Method = "GET",
        [hashtable]$Headers = @{},
        [string]$Body,
        [int]$ExpectedStatus = 200,
        [string]$ExpectedContains
    )

    Write-Info "$Method $Url"
    try {
        $params = @{
            Uri             = $Url
            Method          = $Method
            Headers         = $Headers
            UseBasicParsing = $true
            ErrorAction     = "Stop"
        }
        if ($Body) { $params.Body = $Body }
        $response = Invoke-WebRequest @params
        $status = [int]$response.StatusCode
        $content = $response.Content
    } catch {
        # Invoke-WebRequest бросает на не-2xx — но нам нужно увидеть статус
        if ($_.Exception.Response) {
            $status  = [int]$_.Exception.Response.StatusCode
            $stream  = $_.Exception.Response.GetResponseStream()
            $reader  = New-Object System.IO.StreamReader($stream)
            $content = $reader.ReadToEnd()
        } else {
            Write-Fail "Запрос упал: $($_.Exception.Message)"
            return $false
        }
    }

    if ($status -ne $ExpectedStatus) {
        Write-Fail "Статус $status (ожидался $ExpectedStatus)"
        Write-Host "    Тело: $($content.Substring(0, [Math]::Min(200, $content.Length)))"
        return $false
    }
    if ($ExpectedContains -and ($content -notmatch [regex]::Escape($ExpectedContains))) {
        Write-Fail "Тело не содержит '$ExpectedContains'"
        Write-Host "    Получено: $($content.Substring(0, [Math]::Min(200, $content.Length)))"
        return $false
    }
    Write-OK "$status — $($content.Substring(0, [Math]::Min(80, $content.Length)))"
    return $true
}

function Action-Http {
    Write-Header "HTTP-тесты эндпоинтов"

    if (-not $BaseURL) {
        Write-Fail "Не задан -BaseURL — HTTP-тесты пропущены."
        Write-Info "Для теста опубликуйте базу и запустите с -BaseURL http://localhost/MyBase"
        return $false
    }

    $base = $BaseURL.TrimEnd('/')
    $errors = 0

    # 1. Ping
    if (-not (Test-HttpEndpoint -Url "$base/hs/http/ping" -ExpectedStatus 200 -ExpectedContains "Пинг")) {
        $errors++
    }

    # 2. Swagger JSON
    if (-not (Test-HttpEndpoint -Url "$base/hs/swagger/swagger.json" -ExpectedStatus 200 -ExpectedContains "openapi")) {
        $errors++
    }

    # 3. JRPC demo.echo
    $echoBody = '{"jsonrpc":"2.0","method":"demo.echo","params":{"hello":"world"},"id":1}'
    if (-not (Test-HttpEndpoint -Url "$base/hs/jrpc/call" -Method POST `
            -Headers @{ "Content-Type" = "application/json" } `
            -Body $echoBody -ExpectedStatus 200 -ExpectedContains '"hello":"world"')) {
        $errors++
    }

    # 4. JRPC demo.sum
    $sumBody = '{"jsonrpc":"2.0","method":"demo.sum","params":[2,3],"id":2}'
    if (-not (Test-HttpEndpoint -Url "$base/hs/jrpc/call" -Method POST `
            -Headers @{ "Content-Type" = "application/json" } `
            -Body $sumBody -ExpectedStatus 200 -ExpectedContains '"result":5')) {
        $errors++
    }

    # 5. JRPC unknown method → -32601
    $unknownBody = '{"jsonrpc":"2.0","method":"unknown.method","id":3}'
    if (-not (Test-HttpEndpoint -Url "$base/hs/jrpc/call" -Method POST `
            -Headers @{ "Content-Type" = "application/json" } `
            -Body $unknownBody -ExpectedStatus 200 -ExpectedContains '"code":-32601')) {
        $errors++
    }

    if ($errors -gt 0) {
        Write-Fail "Провалено тестов: $errors"
        return $false
    }
    Write-OK "Все HTTP-тесты пройдены"
    return $true
}

# ---------- Main ----------

Write-Header "http_HTTPСервер — дымовой тест"
Write-Info "Action:        $Action"
Write-Info "CfeFile:       $CfeFile"
if ($BasePath)         { Write-Info "BasePath:      $BasePath" }
if ($Server -and $InfoBase) { Write-Info "Server/IB:     $Server\$InfoBase" }
if ($BaseURL)          { Write-Info "BaseURL:       $BaseURL" }

$success = $true

switch ($Action) {
    "install" { $success = Action-Install }
    "verify"  { $success = Action-Verify }
    "remove"  { $success = Action-Remove }
    "http"    { $success = Action-Http }
    "all" {
        if (-not (Action-Install)) { $success = $false; break }
        if (-not (Action-Verify))  { $success = $false; break }
        if ($BaseURL) {
            if (-not (Action-Http)) { $success = $false }
        } else {
            Write-Info "BaseURL не задан — HTTP-тесты пропущены"
        }
    }
}

Write-Header "Результат: $(if ($success) { 'УСПЕХ' } else { 'ОШИБКИ' })"
if (-not $success) { exit 1 }

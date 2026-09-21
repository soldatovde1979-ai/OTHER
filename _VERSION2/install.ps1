# install.ps1 — универсальное ядро версионирования сборки v2 (шаблон)
#
# Что это:
#   Ядро релиза, не знающее, ЧТО собирается (Excel-книга, база 1С, веб, exe).
#   Вся специфика артефакта — в АДАПТЕРЕ (adapters\<тип>\) по контракту
#   spec-version-contract.md. Ядро знает «когда и в каком порядке», адаптер —
#   «как именно».
#
# Поток релиза:
#   дайджест исходников -> защита от отката -> сборка адаптера -> проверка
#   адаптера -> версия + счётчик релизов -> миграции -> штамп в артефакт ->
#   VERSION / release.state / CHANGELOG.md / build-info.json.
#   Версия фиксируется ТОЛЬКО при нулевом коде сборки и проверки.
#
# Использование (из корня проекта, артефакт закрыт):
#   powershell -NoProfile -ExecutionPolicy Bypass -File install\install.ps1
#   powershell -NoProfile -ExecutionPolicy Bypass -File install\install.ps1 -DryRun
#   powershell -NoProfile -ExecutionPolicy Bypass -File install\install.ps1 -Bump minor
#   powershell -NoProfile -ExecutionPolicy Bypass -File install\install.ps1 -Force
#
# Файл обязательно UTF-8 с BOM: PowerShell 5.1 иначе читает кириллицу как ANSI.

param(
    # ТОЧКА АДАПТАЦИИ: цель установки по умолчанию (файл артефакта или каталог).
    # Относительный путь резолвится от корня проекта (папки выше папки скрипта).
    [string]$Target = ".\<ПУТЬ_К_АРТЕФАКТУ>",
    [ValidateSet("patch", "minor", "major")]
    [string]$Bump = "patch",
    [switch]$DryRun,
    [switch]$Force,
    # ТОЧКА АДАПТАЦИИ: папка адаптера (относительно корня проекта).
    [string]$AdapterDir = ".\install\adapter",
    [string]$ProjectRoot = ""
)

$ErrorActionPreference = "Stop"
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

# ================================================================== точки адаптации
# ТОЧКА АДАПТАЦИИ: имя проекта — попадает в заголовок CHANGELOG.md и манифест.
$ProjectName = "<ИмяПроекта>"

# ТОЧКА АДАПТАЦИИ: исходники, чьё изменение поднимает версию (относительно
# корня проекта). Пока список пуст, релиз не стартует.
$SourceItems = @()

# ТОЧКА АДАПТАЦИИ: метка типа адаптера для манифеста (например, "excel").
$AdapterType = "<тип>"

# ТОЧКА АДАПТАЦИИ: номер первого релиза счётчика. Проекту с историей из N
# релизов — задать N+1; новому проекту — 1.
$StartReleaseNo = 1

# ТОЧКА АДАПТАЦИИ: файл журнала (можно оставить пустым — тогда только консоль).
$LogFile = ""

$scriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
if ($ProjectRoot -eq "") { $root = Split-Path -Parent $scriptRoot } else { $root = $ProjectRoot }
$versionFile = Join-Path $scriptRoot "VERSION"
$stateFile  = Join-Path $scriptRoot "release.state"
$buildInfo  = Join-Path $scriptRoot "build-info.json"
$migDir     = Join-Path $scriptRoot "migrations"
$changelog  = Join-Path $root "CHANGELOG.md"

$fullTarget = $Target
if (-not [System.IO.Path]::IsPathRooted($fullTarget)) { $fullTarget = Join-Path $root $fullTarget }
$fullTarget = [System.IO.Path]::GetFullPath($fullTarget)

$fullAdapterDir = $AdapterDir
if (-not [System.IO.Path]::IsPathRooted($fullAdapterDir)) { $fullAdapterDir = Join-Path $root $fullAdapterDir }
$fullAdapterDir = [System.IO.Path]::GetFullPath($fullAdapterDir)

# ================================================================== логирование
# Маркерный лог: одна строка на событие, формат «МАРКЕР детали - пояснение».
function Write-Marker([string]$marker, [string]$message) {
    $line = $marker + " " + $message
    Write-Output $line
    if ($LogFile -ne "") {
        Add-Content -LiteralPath $LogFile -Encoding UTF8 -Value ((Get-Date -Format "yyyy-MM-dd HH:mm:ss") + " " + $line)
    }
}

function Fail([string]$msg) { Write-Marker "RELEASE_FAIL" $msg; exit 1 }

# ================================================================== версия
function Read-BuildVersion() {
    if (-not (Test-Path $versionFile)) { Fail ("нет файла " + $versionFile) }
    $lines = Get-Content -LiteralPath $versionFile -Encoding UTF8
    foreach ($l in $lines) {
        $t = $l.Trim()
        if ($t -ne "") {
            if ($t -notmatch "^\d+\.\d+\.\d+$") { Fail ("первая строка VERSION не версия вида 1.2.3: " + $t) }
            return $t
        }
    }
    Fail "файл VERSION пуст"
}

# Человеческое описание: все непустые строки ниже первой непустой (версии).
function Read-VersionDescription() {
    $lines = Get-Content -LiteralPath $versionFile -Encoding UTF8
    $seen = $false
    $out = @()
    foreach ($l in $lines) {
        if (-not $seen) { if ($l.Trim() -ne "") { $seen = $true }; continue }
        if ($l.Trim() -eq "") { continue }
        $out += $l
    }
    return $out
}

# SemVer: МАЖОР.МИНОР.ПАТЧ.
function Step-Version([string]$ver, [string]$kind) {
    $p = $ver.Split(".")
    $ma = [int]$p[0]; $mi = [int]$p[1]; $pa = [int]$p[2]
    if ($kind -eq "major") { $ma += 1; $mi = 0; $pa = 0 }
    elseif ($kind -eq "minor") { $mi += 1; $pa = 0 }
    else { $pa += 1 }
    return ("" + $ma + "." + $mi + "." + $pa)
}

function Compare-Version([string]$a, [string]$b) {
    $pa = $a.Split("."); $pb = $b.Split(".")
    for ($i = 0; $i -lt 3; $i++) {
        $da = [int]$pa[$i]; $db = [int]$pb[$i]
        if ($da -gt $db) { return 1 }
        if ($da -lt $db) { return -1 }
    }
    return 0
}

# ================================================================== дайджест исходников
function Get-SourceMap() {
    $map = New-Object System.Collections.Specialized.OrderedDictionary
    $files = @()
    foreach ($item in $SourceItems) {
        $full = $item
        if (-not [System.IO.Path]::IsPathRooted($full)) { $full = Join-Path $root $full }
        if (Test-Path -LiteralPath $full -PathType Container) {
            $files += Get-ChildItem -Path $full -Recurse -File
        } elseif (Test-Path -LiteralPath $full -PathType Leaf) {
            $files += Get-Item -LiteralPath $full
        } else {
            Write-Marker "SOURCE_MISSING" ($full + " - исходник не найден, в дайджест не входит")
        }
    }
    foreach ($f in ($files | Sort-Object FullName -Unique)) {
        $rel = $f.FullName.Substring($root.Length).TrimStart("\", "/")
        $md5 = New-Object System.Security.Cryptography.MD5CryptoServiceProvider
        $bytes = [IO.File]::ReadAllBytes($f.FullName)
        $hash = [BitConverter]::ToString($md5.ComputeHash($bytes)) -replace "-", ""
        $map[$rel] = $hash.ToLower()
    }
    return $map
}

function Get-MapDigest($map) {
    $md5 = New-Object System.Security.Cryptography.MD5CryptoServiceProvider
    $sb = New-Object System.Text.StringBuilder
    foreach ($k in $map.Keys) { [void]$sb.Append($k + "=" + $map[$k] + "`n") }
    $bytes = [System.Text.Encoding]::UTF8.GetBytes($sb.ToString())
    return ([BitConverter]::ToString($md5.ComputeHash($bytes)) -replace "-", "").ToLower()
}

# ================================================================== состояние прошлого релиза
function Read-State() {
    $state = @{ Version = ""; Digest = ""; ReleaseNo = 0; Files = @{} }
    if (-not (Test-Path $stateFile)) { return $state }
    foreach ($raw in (Get-Content -LiteralPath $stateFile -Encoding UTF8)) {
        $t = $raw.Trim()
        if ($t -eq "") { continue }
        $parts = $t -split " ", 3
        if ($parts[0] -eq "version") { $state.Version = $parts[1] }
        elseif ($parts[0] -eq "digest") { $state.Digest = $parts[1] }
        elseif ($parts[0] -eq "release_no") { $state.ReleaseNo = [int]$parts[1] }
        elseif ($parts[0] -eq "file") { $state.Files[$parts[1]] = $parts[2] }
    }
    return $state
}

function Write-State([string]$ver, $map, [string]$digest, [int]$releaseNo) {
    $lines = @("version " + $ver, "digest " + $digest, "release_no " + $releaseNo)
    foreach ($k in $map.Keys) { $lines += ("file " + $k + " " + $map[$k]) }
    [IO.File]::WriteAllLines($stateFile, $lines, (New-Object System.Text.UTF8Encoding($false)))
}

# ================================================================== манифест сборки
function Write-BuildInfo([string]$ver, [int]$releaseNo, [string]$digest, $map) {
    $files = @()
    foreach ($k in $map.Keys) { $files += @{ path = $k; md5 = $map[$k] } }
    $obj = @{
        project    = $ProjectName
        adapter    = $AdapterType
        release_no = $releaseNo
        version    = $ver
        date       = (Get-Date -Format "yyyy-MM-dd HH:mm")
        digest     = $digest
        files      = $files
    }
    $json = $obj | ConvertTo-Json -Depth 4
    [IO.File]::WriteAllText($buildInfo, $json, (New-Object System.Text.UTF8Encoding($false)))
}

# ================================================================== адаптер
# Вызов файла адаптера в отдельном процессе; возвращает код возврата.
function Invoke-AdapterScript([string]$file, [string[]]$args) {
    $out = & powershell -NoProfile -ExecutionPolicy Bypass -File $file @args
    $out | ForEach-Object { Write-Output ("ADAPTER " + $_) }
    return $LASTEXITCODE
}

function Invoke-AdapterBuild() {
    Write-Marker "STEP" "--- ШАГ 1: сборка/установка артефакта (адаптер)"
    $build = Join-Path $fullAdapterDir "build.ps1"
    if (-not (Test-Path $build)) { Fail ("нет адаптера сборки: " + $build) }
    $code = Invoke-AdapterScript $build @("-Target", $fullTarget, "-SourceRoot", $root)
    if ($code -ne 0) { Fail ("сборка вернула код " + $code + " - версия не изменена") }
    Write-Marker "BUILD_OK" "сборка/установка завершена с кодом 0"
}

function Invoke-AdapterVerify() {
    Write-Marker "STEP" "--- ШАГ 2: проверка артефакта (адаптер)"
    $verify = Join-Path $fullAdapterDir "verify.ps1"
    if (-not (Test-Path $verify)) { Write-Marker "VERIFY_SKIP" "проверки нет, считается успешной"; return }
    $code = Invoke-AdapterScript $verify @("-Target", $fullTarget)
    if ($code -ne 0) { Fail ("проверка вернула код " + $code + " - версия не изменена") }
    Write-Marker "VERIFY_OK" "проверка завершена с кодом 0"
}

function Read-Stamp() {
    $stamp = Join-Path $fullAdapterDir "stamp.ps1"
    if (-not (Test-Path $stamp)) { Fail ("нет адаптера штампа: " + $stamp) }
    $out = & powershell -NoProfile -ExecutionPolicy Bypass -File $stamp -Target $fullTarget -Read
    $info = @{ Version = "0.0.0"; Date = ""; Md5 = ""; ReleaseNo = 0 }
    foreach ($line in $out) {
        if ($line -match "^STAMP_VERSION (.*)$") { $info.Version = $Matches[1].Trim() }
        elseif ($line -match "^STAMP_DATE (.*)$") { $info.Date = $Matches[1].Trim() }
        elseif ($line -match "^STAMP_MD5 (.*)$") { $info.Md5 = $Matches[1].Trim() }
        elseif ($line -match "^STAMP_RELEASE_NO (.*)$") { $info.ReleaseNo = [int]$Matches[1].Trim() }
    }
    if ($info.Version -notmatch "^\d+\.\d+\.\d+$") { $info.Version = "0.0.0" }
    return $info
}

function Write-Stamp([string]$ver, [string]$date, [string]$digest, [int]$releaseNo) {
    $stamp = Join-Path $fullAdapterDir "stamp.ps1"
    if (-not (Test-Path $stamp)) { Fail ("нет адаптера штампа: " + $stamp) }
    $code = Invoke-AdapterScript $stamp @("-Target", $fullTarget,
        "-Version", $ver, "-Date", $date, "-Md5", $digest, "-ReleaseNo", ("" + $releaseNo))
    if ($code -ne 0) { Fail "штамп в артефакт не записан - версия не изменена" }
    Write-Marker "STAMP_WRITTEN" ($ver + " (" + $releaseNo + ")")
}

function Invoke-Migration([string]$migPath) {
    $ctx = Join-Path $fullAdapterDir "context.ps1"
    if (-not (Test-Path $ctx)) { Fail ("нет адаптера контекста: " + $ctx) }
    $code = Invoke-AdapterScript $ctx @("-Target", $fullTarget, "-Migration", $migPath)
    if ($code -ne 0) { Fail ("миграция " + (Split-Path $migPath -Leaf) + " вернула код " + $code) }
}

# ================================================================== старт
if ($SourceItems.Count -eq 0) { Fail "ТОЧКА АДАПТАЦИИ: заполните список исходников `$SourceItems" }
if ($ProjectName -eq "<ИмяПроекта>") { Fail "ТОЧКА АДАПТАЦИИ: задайте `$ProjectName" }
if ($AdapterType -eq "<тип>") { Fail "ТОЧКА АДАПТАЦИИ: задайте `$AdapterType" }

$curVersion = Read-BuildVersion
$map = Get-SourceMap
$digest = Get-MapDigest $map
$state = Read-State

$changedFiles = @()
foreach ($k in $map.Keys) {
    $old = ""
    if ($state.Files.ContainsKey($k)) { $old = $state.Files[$k] }
    if ($old -ne $map[$k]) { $changedFiles += $k }
}
foreach ($k in $state.Files.Keys) { if (-not $map.Contains($k)) { $changedFiles += ($k + " (удалён)") } }

$sourcesChanged = ($digest -ne $state.Digest)
$newVersion = $curVersion
if ($sourcesChanged -and $state.Digest -ne "") { $newVersion = Step-Version $curVersion $Bump }

Write-Marker "RELEASE_TARGET" ($fullTarget + " - цель установки (полный путь)")
Write-Marker "RELEASE_VERSION_CURRENT" ($curVersion + " - версия из файла VERSION")
if ($state.Digest -eq "") {
    Write-Marker "RELEASE_FIRST_RUN" "прошлого состояния нет, версия не поднимается, фиксируем текущую"
} elseif ($sourcesChanged) {
    Write-Marker "RELEASE_SOURCES_CHANGED" ($changedFiles.Count + " - изменились: " + ($changedFiles -join ", "))
    Write-Marker "RELEASE_VERSION_NEXT" ($newVersion + " - поднимаем (" + $Bump + ")")
} else {
    Write-Marker "RELEASE_SOURCES_SAME" "исходники не менялись, версия остаётся прежней"
}

# Человеческое описание для CHANGELOG: заполняется руками в install\VERSION ниже
# первой строки ДО релиза. Читаем до записи VERSION (запись сбрасывает описание).
$desc = @(Read-VersionDescription)
if ($desc.Count -gt 0) {
    Write-Marker "DESC_FOUND" ($desc.Count + " - описание для CHANGELOG прочитано из install\VERSION")
} else {
    Write-Marker "DESC_EMPTY" "описание не заполнено - впишите его в install\VERSION ниже первой строки до релиза"
}

if (-not (Test-Path $fullTarget)) {
    Write-Marker "TARGET_NOT_FOUND" ($fullTarget + " - цель сейчас не существует; если сборка создаёт её заново, это нормально")
}

if ($DryRun) {
    Write-Marker "RELEASE_DRYRUN" "артефакт не тронут, версия не записана"
    exit 0
}

# ================================================================== защита от отката
# Штамп артефакта против версии исходников: старый код поверх нового не ставится.
$forced = $false
if (Test-Path $fullTarget) {
    $stampBefore = Read-Stamp
    Write-Marker "ARTIFACT_VERSION" ($stampBefore.Version + " - версия, записанная в артефакте до этого прогона")
    $cmp = Compare-Version $stampBefore.Version $curVersion
    if ($cmp -gt 0) {
        if (-not $Force) {
            Fail ("артефакт НОВЕЕ исходников: в артефакте " + $stampBefore.Version + ", в install\VERSION " + $curVersion + " - осознанный откат: тот же запуск с флагом -Force")
        }
        $forced = $true
        Write-Marker "FORCE_DOWNGRADE" ($stampBefore.Version + " -> " + $curVersion + " - откат по флагу -Force, записываем в журнал")
    } elseif ($cmp -eq 0 -and $stampBefore.Md5 -ne "" -and $stampBefore.Md5 -ne $digest) {
        Write-Marker "BOOK_MD5_MISMATCH" ($stampBefore.Md5 + " - в артефакте та же версия " + $stampBefore.Version + ", но другое содержимое: похоже, релиз делали с другой машины")
    }
}

# ================================================================== сборка и проверка
Invoke-AdapterBuild
Invoke-AdapterVerify

# ================================================================== версия, счётчик, миграции, штамп
Write-Marker "STEP" "--- ШАГ 3: версия, счётчик релизов и миграции"
$newReleaseNo = [int]$state.ReleaseNo
if ($newReleaseNo -le 0) { $newReleaseNo = [int]$StartReleaseNo } else { $newReleaseNo += 1 }
Write-Marker "RELEASE_NO" ($newReleaseNo + " - счётчик релизов после инкремента")

$artifactVersion = Read-Stamp
if ($artifactVersion.Version -notmatch "^\d+\.\d+\.\d+$") { $artifactVersion.Version = "0.0.0" }
Write-Marker "ARTIFACT_VERSION" ($artifactVersion.Version + " - версия в артефакте для гейтинга миграций")

$applied = @()
if (Test-Path $migDir) {
    $migs = Get-ChildItem -Path $migDir -Filter *.ps1 -File | Where-Object { $_.Name -match "^(\d+\.\d+\.\d+)__" } |
        Sort-Object @{ Expression = { [version]($_.Name -replace '^(\d+\.\d+\.\d+)__.*$', '$1') } }
    foreach ($m in $migs) {
        $mv = ($m.Name -replace '^(\d+\.\d+\.\d+)__.*$', '$1')
        if ((Compare-Version $mv $artifactVersion.Version) -le 0) {
            Write-Marker "MIG_SKIP" ($m.Name + " - версия артефакта уже " + $artifactVersion.Version)
            continue
        }
        $reqFrom = "0.0.0"
        foreach ($line in (Get-Content -LiteralPath $m.FullName -Encoding UTF8 -TotalCount 20)) {
            if ($line -match "^#\s*requires-from:\s*(\d+\.\d+\.\d+)") { $reqFrom = $Matches[1] }
        }
        if ((Compare-Version $artifactVersion.Version $reqFrom) -lt 0) {
            Fail ("миграция " + $m.Name + " требует артефакт не ниже " + $reqFrom + ", а в нём " + $artifactVersion.Version + " - поставьте промежуточную версию")
        }
        Write-Marker "MIG_RUN" ($m.Name + " - применяем через адаптер")
        Invoke-Migration $m.FullName
        $applied += $m.Name
    }
}

$stampDate = (Get-Date -Format "dd.MM.yyyy HH:mm")
Write-Stamp $newVersion $stampDate $digest $newReleaseNo

# ================================================================== VERSION, state, CHANGELOG, манифест
if ($newVersion -ne $curVersion) {
    # Описание ушло в CHANGELOG этой записи; VERSION сбрасывается под описание
    # следующей версии, чтобы старое описание не продублировалось в след. релизе.
    $lines = @()
    $lines += $newVersion
    $lines += ""
    $lines += "Первая строка этого файла - версия сборки, её ведёт install.ps1."
    $lines += "Ниже, до следующего релиза, впишите человеческое описание изменений:"
    $lines += "  что добавлено; какая ошибка исправлена; что и с каким результатом оптимизировано."
    $lines += "Оно попадёт в CHANGELOG.md первым абзацем записи новой версии."
    [IO.File]::WriteAllLines($versionFile, $lines, (New-Object System.Text.UTF8Encoding($false)))
    Write-Marker "VERSION_WRITTEN" $newVersion
}

Write-State $newVersion $map $digest $newReleaseNo
Write-Marker "STATE_WRITTEN" "release.state"

Write-BuildInfo $newVersion $newReleaseNo $digest $map
Write-Marker "BUILDINFO_WRITTEN" "build-info.json"

# Запись в CHANGELOG не дублируется при неизменных исходниках без миграций и
# без -Force: пишется только при изменении исходников, откате или миграциях.
if (-not $sourcesChanged -and -not $forced -and ($applied.Count -eq 0)) {
    Write-Marker "CHANGELOG_SKIP" "исходники не менялись, запись не дублируется"
} else {
    $entry = @()
    $entry += ("## " + $newVersion + " (" + $newReleaseNo + ") " + [char]0x2014 + " " + (Get-Date -Format "dd.MM.yyyy"))
    $entry += ""
    # Сначала человеческое описание (из install\VERSION), техника - строго после.
    if ($desc.Count -gt 0) {
        $entry += $desc
        $entry += ""
    } else {
        $entry += "- Описание изменений не заполнено: впишите его в install\VERSION ниже первой строки до релиза"
        $entry += ""
    }
    if ($changedFiles.Count -gt 0) { $entry += ("- Изменены исходники: " + ($changedFiles -join ", ")) }
    else { $entry += "- Исходники не менялись, переустановка в артефакт" }
    if ($applied.Count -gt 0) { $entry += ("- Миграции: " + ($applied -join ", ")) }
    if ($forced) { $entry += ("- ВНИМАНИЕ: установлено с -Force поверх более новой версии артефакта") }
    $entry += ("- Артефакт: " + $fullTarget)
    $entry += ("- Хеш исходников: " + $digest)
    $entry += ""

    if (Test-Path $changelog) {
        $old = Get-Content -LiteralPath $changelog -Encoding UTF8
        $idx = -1
        for ($i = 0; $i -lt $old.Count; $i++) { if ($old[$i] -like "## *") { $idx = $i; break } }
        if ($idx -lt 0) { $new = $old + "" + $entry }
        elseif ($idx -eq 0) { $new = ($entry + $old) }
        else { $new = ($old[0..($idx - 1)] + $entry + $old[$idx..($old.Count - 1)]) }
    } else {
        $head = @("# Журнал версий " + $ProjectName, "", "Формат: человеческое описание изменений, затем техническая часть; новая запись сверху. Файл ведёт install\install.ps1.", "")
        $new = $head + $entry
    }
    [IO.File]::WriteAllLines($changelog, $new, (New-Object System.Text.UTF8Encoding($false)))
    Write-Marker "CHANGELOG_WRITTEN" "CHANGELOG.md"
}

Write-Marker "RELEASE_OK" ($newVersion + " (" + $newReleaseNo + ") - артефакт " + $fullTarget)
exit 0

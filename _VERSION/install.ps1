# install.ps1 — универсальный механизм версионирования сборки (шаблон)
#
# Что это:
#   Объединение двух ролей: «install» (установка) + «release» (версионирование).
#   1) считает хеши исходников и сравнивает с прошлым релизом (release.state);
#   2) если исходники не менялись — версия остаётся прежней (повторный прогон
#      не накручивает номер);
#   3) выполняет установку/сборку артефакта (точка адаптации);
#   4) ТОЛЬКО если сборка вернула 0: поднимает версию (по умолчанию патч,
#      -Bump minor|major — руками при смене контракта), пишет её в артефакт,
#      прогоняет недостающие миграции и добавляет запись в CHANGELOG.md.
#
# Проектная нейтральность:
#   Скрипт не знает, ЧТО собирается (Excel-книга, база 1С, веб-сайт, exe).
#   Всё, что зависит от артефакта, вынесено в ТОЧКИ АДАПТАЦИИ — ищите строку
#   «ТОЧКА АДАПТАЦИИ». До их заполнения скрипт останавливается с понятным
#   сообщением и не поднимает версию.
#
# Использование (из корня проекта, артефакт должен быть закрыт):
#   powershell -NoProfile -ExecutionPolicy Bypass -File install\install.ps1
#   powershell -NoProfile -ExecutionPolicy Bypass -File install\install.ps1 -DryRun
#   powershell -NoProfile -ExecutionPolicy Bypass -File install\install.ps1 -Bump minor
#   powershell -NoProfile -ExecutionPolicy Bypass -File install\install.ps1 -Target ".\<артефакт>"
#
# Файл обязательно UTF-8 с BOM: PowerShell 5.1 иначе читает кириллицу как ANSI.

param(
    # ТОЧКА АДАПТАЦИИ: цель установки по умолчанию (файл артефакта или каталог).
    # Относительный путь резолвится от корня проекта (папки выше папки скрипта).
    [string]$Target = ".\<ПУТЬ_К_АРТЕФАКТУ>",
    [ValidateSet("patch", "minor", "major")]
    [string]$Bump = "patch",
    [switch]$DryRun
)

$ErrorActionPreference = "Stop"
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

# ТОЧКА АДАПТАЦИИ: имя проекта — попадает в заголовок CHANGELOG.md.
$ProjectName = "<ИмяПроекта>"

# ТОЧКА АДАПТАЦИИ: файл журнала (можно оставить пустым — тогда только консоль).
# Пример: $LogFile = Join-Path $scriptRoot "release.log"
$LogFile = ""

$scriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$root = Split-Path -Parent $scriptRoot
$versionFile = Join-Path $scriptRoot "VERSION"
$stateFile = Join-Path $scriptRoot "release.state"
$migDir = Join-Path $scriptRoot "migrations"
$changelog = Join-Path $root "CHANGELOG.md"

# ---------------------------------------------------------------- логирование
# Маркерный лог: одна строка на событие, формат «МАРКЕР детали - пояснение».
# Человек, CI и агент ищут маркеры, а не разбирают свободный текст.
function Write-Marker([string]$marker, [string]$message) {
    $line = $marker + " " + $message
    Write-Output $line
    if ($LogFile -ne "") {
        Add-Content -LiteralPath $LogFile -Encoding UTF8 -Value ((Get-Date -Format "yyyy-MM-dd HH:mm:ss") + " " + $line)
    }
}

# Единственный способ прервать релиз: маркер RELEASE_FAIL и код возврата 1.
function Fail([string]$msg) { Write-Marker "RELEASE_FAIL" $msg; exit 1 }

# ---------------------------------------------------------------- версия
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

function Read-VersionDescription() {
    $lines = Get-Content -LiteralPath $versionFile -Encoding UTF8
    $seen = $false
    $out = @()
    foreach ($l in $lines) {
        if (-not $seen) { if ($l.Trim() -ne "") { $seen = $true }; continue }
        $out += $l
    }
    return ($out -join " ").Trim()
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
        $x = [int]$pa[$i]; $y = [int]$pb[$i]
        if ($x -lt $y) { return -1 }
        if ($x -gt $y) { return 1 }
    }
    return 0
}

# ---------------------------------------------------------------- хеши исходников
# ТОЧКА АДАПТАЦИИ: перечислите каталоги и файлы исходников, чьё изменение
# поднимает версию. Относительные пути — от корня проекта. Каталог считается
# рекурсивно (все файлы внутри). Пока список пуст, релиз не стартует.
$SourceItems = @(
    # "src\...",
    # "config\...",
    # "main.file"
)

function Get-SourceMap() {
    $map = New-Object System.Collections.Specialized.OrderedDictionary
    $rootLen = $root.Length
    foreach ($item in $SourceItems) {
        $path = Join-Path $root $item
        if (Test-Path -LiteralPath $path -PathType Leaf) {
            $files = @(Get-Item -LiteralPath $path)
        } elseif (Test-Path -LiteralPath $path -PathType Container) {
            $files = @(Get-ChildItem -LiteralPath $path -Recurse -File)
        } else {
            Fail ("путь из `$SourceItems не найден: " + $item)
        }
        foreach ($f in $files) {
            $rel = $f.FullName.Substring($rootLen).TrimStart("\", "/")
            $h = (Get-FileHash -Algorithm MD5 -LiteralPath $f.FullName).Hash
            $map[$rel] = $h
        }
    }
    return $map
}

function Get-MapDigest($map) {
    $sb = New-Object System.Text.StringBuilder
    foreach ($k in $map.Keys) { [void]$sb.Append($k); [void]$sb.Append(" "); [void]$sb.Append($map[$k]); [void]$sb.Append("`n") }
    $md5 = [System.Security.Cryptography.MD5]::Create()
    $bytes = [System.Text.Encoding]::UTF8.GetBytes($sb.ToString())
    $hash = $md5.ComputeHash($bytes)
    return (($hash | ForEach-Object { $_.ToString("x2") }) -join "")
}

function Read-State() {
    $state = @{ Version = ""; Digest = ""; Files = @{} }
    if (-not (Test-Path $stateFile)) { return $state }
    foreach ($l in (Get-Content -LiteralPath $stateFile -Encoding UTF8)) {
        $t = $l.Trim()
        if ($t -eq "" -or $t.StartsWith("#")) { continue }
        $parts = $t -split " ", 3
        if ($parts[0] -eq "version") { $state.Version = $parts[1] }
        elseif ($parts[0] -eq "digest") { $state.Digest = $parts[1] }
        elseif ($parts[0] -eq "file") { $state.Files[$parts[1]] = $parts[2] }
    }
    return $state
}

function Write-State([string]$ver, $map, [string]$digest) {
    $lines = @()
    $lines += "# Служебный файл install.ps1 - состояние последнего успешного релиза."
    $lines += "# Руками не править: отсюда берётся ответ на вопрос «менялись ли исходники»."
    $lines += ("version " + $ver)
    $lines += ("digest " + $digest)
    foreach ($k in $map.Keys) { $lines += ("file " + $k + " " + $map[$k]) }
    [IO.File]::WriteAllLines($stateFile, $lines, (New-Object System.Text.UTF8Encoding($false)))
}

# ---------------------------------------------------------------- артефакт: версия
# ТОЧКА АДАПТАЦИИ: прочитать версию, уже записанную в артефакте ("" — если нет).
# Пустое значение означает 0.0.0: применятся все миграции, подходящие по requires-from.
function Read-ArtifactVersion([string]$target, $context) {
    # Пример (книга с таблицей «ключ-значение»): Get-VariableKey $context "BUILD/VERSION"
    # Пример (web): (Get-Content (Join-Path $target "version.json") | ConvertFrom-Json).version
    return ""
}

# ТОЧКА АДАПТАЦИИ: записать в артефакт версию, дату сборки и хеш исходников.
# При сбое — throw: версия не должна фиксироваться на артефакте, в который её
# записать не удалось (правило «версия только при нулевом коде»).
function Write-VersionToArtifact([string]$target, $context, [string]$ver, [string]$date, [string]$digest) {
    # Пример (книга): Set-VariableKey $context "BUILD/VERSION" $ver
    # Пример (1С): константа/регистр сведений с версией конфигурации
    # Пример (web): [IO.File]::WriteAllText((Join-Path $target "version.json"), ...)
    throw "ТОЧКА АДАПТАЦИИ: вставьте запись BUILD/VERSION, BUILD/DATE, BUILD/SRC_MD5 в артефакт"
}

# ================================================================== старт
if ($SourceItems.Count -eq 0) { Fail "ТОЧКА АДАПТАЦИИ: заполните список исходников `$SourceItems" }

# Цель установки резолвится от корня проекта.
$fullTarget = $Target
if (-not [System.IO.Path]::IsPathRooted($fullTarget)) { $fullTarget = Join-Path $root $fullTarget }
$fullTarget = [System.IO.Path]::GetFullPath($fullTarget)

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

Write-Marker "TARGET" ($fullTarget + " - цель установки (полный путь)")
Write-Marker "RELEASE_VERSION_CURRENT" ($curVersion + " - версия из файла VERSION")
if ($state.Digest -eq "") {
    Write-Marker "RELEASE_FIRST_RUN" "прошлого состояния нет, версия не поднимается, фиксируем текущую"
} elseif ($sourcesChanged) {
    Write-Marker "RELEASE_SOURCES_CHANGED" ($changedFiles.Count + " - изменились: " + ($changedFiles -join ", "))
    Write-Marker "RELEASE_VERSION_NEXT" ($newVersion + " - поднимаем (" + $Bump + ")")
} else {
    Write-Marker "RELEASE_SOURCES_SAME" "исходники не менялись, версия остаётся прежней"
}

if (-not (Test-Path $fullTarget)) {
    Write-Marker "TARGET_NOT_FOUND" ($fullTarget + " - цель сейчас не существует; если сборка создаёт её заново, это нормально")
}

if ($DryRun) {
    Write-Marker "RELEASE_DRYRUN" "артефакт не тронут, версия не записана"
    exit 0
}

# ---------------------------------------------------------------- сборка
Write-Marker "STEP" "--- ШАГ 1: установка/сборка артефакта"
# ===== [тут код для сборки билда/релиза] =====
# ТОЧКА АДАПТАЦИИ: замените строки ниже вызовом сборщика/инсталлера проекта.
# Требования: успех -> код возврата 0; сбой -> любой ненулевой код.
# Примеры:
#   & powershell -NoProfile -ExecutionPolicy Bypass -File "install\installer.ps1" -Target "$fullTarget"
#   & "C:\Program Files\1cv8\...\1cv8.exe" DESIGNER /F "$fullTarget" /UpdateDBCfg
#   npm run build
#   dotnet publish -c Release
#   if ($LASTEXITCODE -ne 0) { Fail ("сборка вернула " + $LASTEXITCODE + " - версия не изменена") }
Fail "ТОЧКА АДАПТАЦИИ: вставьте код сборки билда/релиза (ищите строку [тут код для сборки билда/релиза])"
Write-Marker "BUILD_OK" "сборка/установка завершена с кодом 0"

# ---------------------------------------------------------------- артефакт: версия и миграции
Write-Marker "STEP" "--- ШАГ 2: версия и миграции в артефакте"
# ТОЧКА АДАПТАЦИИ: контекст для миграций и записи версии (например, открытый
# артефакт). Открывайте его здесь, закрывайте после записи версии.
$context = $null

$applied = @()
try {
    $artifactVersion = Read-ArtifactVersion $fullTarget $context
    if ($artifactVersion -notmatch "^\d+\.\d+\.\d+$") { $artifactVersion = "0.0.0" }
    Write-Marker "ARTIFACT_VERSION" ($artifactVersion + " - версия, записанная в артефакте до этого прогона")

    if (Test-Path $migDir) {
        $migs = Get-ChildItem -Path $migDir -Filter *.ps1 -File | Where-Object { $_.Name -match "^(\d+\.\d+\.\d+)__" } |
            Sort-Object @{ Expression = { [version]($_.Name -replace '^(\d+\.\d+\.\d+)__.*$', '$1') } }
        foreach ($m in $migs) {
            $mv = ($m.Name -replace '^(\d+\.\d+\.\d+)__.*$', '$1')
            if ((Compare-Version $mv $artifactVersion) -le 0) {
                Write-Marker "MIG_SKIP" ($m.Name + " - версия артефакта уже " + $artifactVersion)
                continue
            }
            $reqFrom = "0.0.0"
            foreach ($line in (Get-Content -LiteralPath $m.FullName -Encoding UTF8 -TotalCount 20)) {
                if ($line -match "^#\s*requires-from:\s*(\d+\.\d+\.\d+)") { $reqFrom = $Matches[1] }
            }
            if ((Compare-Version $artifactVersion $reqFrom) -lt 0) {
                throw ("миграция " + $m.Name + " требует артефакт не ниже " + $reqFrom + ", а в нём " + $artifactVersion + " - поставьте промежуточную версию")
            }
            Write-Marker "MIG_RUN" ($m.Name + " - применяем")
            & $m.FullName -Target $fullTarget -Context $context | ForEach-Object { Write-Marker "MIG" ("  " + $_) }
            $applied += $m.Name
        }
    }

    $stampDate = (Get-Date -Format "dd.MM.yyyy HH:mm")
    Write-VersionToArtifact $fullTarget $context $newVersion $stampDate $digest
    Write-Marker "BUILD_VERSION" $newVersion
} catch {
    Write-Marker "ARTIFACT_ERROR" $_.Exception.Message
    Fail "сборка прошла, но версия/миграции в артефакт не записаны - смотрите ARTIFACT_ERROR выше"
}

# ---------------------------------------------------------------- VERSION, state, CHANGELOG
if ($newVersion -ne $curVersion) {
    $desc = Read-VersionDescription
    $lines = @()
    $lines += $newVersion
    $lines += ("Собрано " + (Get-Date -Format "dd.MM.yyyy") + ". Изменены: " + ($changedFiles -join ", "))
    $lines += ""
    $lines += "Первая строка этого файла - версия сборки, всё ниже - описание."
    $lines += "Версию меняет install.ps1, руками править не нужно."
    [IO.File]::WriteAllLines($versionFile, $lines, (New-Object System.Text.UTF8Encoding($false)))
    Write-Marker "VERSION_WRITTEN" $newVersion
}

Write-State $newVersion $map $digest
Write-Marker "STATE_WRITTEN" "release.state"

$entry = @()
$entry += ("## " + $newVersion + " " + [char]0x2014 + " " + (Get-Date -Format "dd.MM.yyyy"))
$entry += ""
if ($changedFiles.Count -gt 0) { $entry += ("- Изменены исходники: " + ($changedFiles -join ", ")) }
else { $entry += "- Исходники не менялись, переустановка в артефакт" }
if ($applied.Count -gt 0) { $entry += ("- Миграции: " + ($applied -join ", ")) }
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
    $head = @("# Журнал версий " + $ProjectName, "", "Формат: Keep a Changelog, новая запись сверху. Файл ведёт install.ps1.", "")
    $new = $head + $entry
}
[IO.File]::WriteAllLines($changelog, $new, (New-Object System.Text.UTF8Encoding($false)))
Write-Marker "CHANGELOG_WRITTEN" "CHANGELOG.md"

Write-Marker "RELEASE_OK" ($newVersion + " - артефакт " + $fullTarget)
exit 0

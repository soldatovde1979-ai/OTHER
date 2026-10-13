# build.ps1 — сборка книги Excel (Excel-адаптер)
#
# Контракт (spec-version-contract.md): успех = код 0, сбой = ненулевой.
# Что делает: бэкап книги в bak\, импорт VBA-модулей (src\vba\*.bas) и
# запросов Power Query (src\powerquery\*.pq), сохранение.
#
# Сигнатура: -Target <книга> -SourceRoot <корень проекта>.
# Точки адаптации внутри: каталоги исходников, перенос шаблона (по проекту).
# Модули перекодируются UTF-8 -> ANSI(1251) перед импортом: VBE 5.1 читает
# их как ANSI.
# UTF-8 с BOM: PowerShell 5.1 иначе читает кириллицу как ANSI.

param(
    [string]$Target,
    [string]$SourceRoot
)

$ErrorActionPreference = "Stop"
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

if ($Target -eq "" -or $SourceRoot -eq "") { Write-Output "BUILD_ERROR - не заданы -Target / -SourceRoot"; exit 1 }
$full = $Target
if (-not [System.IO.Path]::IsPathRooted($full)) { $full = [System.IO.Path]::GetFullPath((Join-Path $SourceRoot $full)) }

# ТОЧКИ АДАПТАЦИИ: каталоги исходников книги.
$vbaDir = Join-Path $SourceRoot "src\vba"
$pqDir  = Join-Path $SourceRoot "src\powerquery"
# ТОЧКА АДАПТАЦИИ: перенос HTML-шаблона/листов — впишите здесь специфику
# проекта (для ReportMTO: запись шаблона в ячейку книги). По умолчанию — нет.

if (-not (Test-Path -LiteralPath $full)) {
    Write-Output ("BUILD_ERROR - книга не найдена: " + $full + ". Соберите её вручную или задайте копию шаблона в точке адаптации")
    exit 1
}

# Бэкап до любых правок.
$bakDir = Join-Path (Split-Path -Parent $full) "bak"
if (-not (Test-Path $bakDir)) { New-Item -ItemType Directory -Path $bakDir | Out-Null }
$bakName = (Split-Path $full -Leaf) + "." + (Get-Date -Format "yyyyMMdd_HHmmss") + ".bak"
Copy-Item $full (Join-Path $bakDir $bakName) -Force
Write-Output ("BACKUP " + $bakName)

$ansi = [System.Text.Encoding]::GetEncoding(1251)
$tempDir = $env:TEMP

$excel = New-Object -ComObject Excel.Application
$excel.Visible = $false
$excel.DisplayAlerts = $false
try {
    $wb = $excel.Workbooks.Open($full, 0, $false)
    try {
        $vp = $wb.VBProject

        if (Test-Path $vbaDir) {
            foreach ($bas in (Get-ChildItem -Path $vbaDir -Filter *.bas -File | Sort-Object Name)) {
                $mod = [System.IO.Path]::GetFileNameWithoutExtension($bas.Name)
                $curComp = $null
                try { $curComp = $vp.VBComponents.Item($mod) } catch { }
                if ($null -ne $curComp) {
                    $vp.VBComponents.Remove($curComp)
                    Write-Output ("VBA_DIFF " + $mod + " - существует, переустановлен из исходника")
                } else {
                    Write-Output ("VBA_ADDED " + $mod + " - модуля не было, добавлен из исходника")
                }
                $utf8 = [System.IO.File]::ReadAllText($bas.FullName)
                $ansiTemp = Join-Path $tempDir ($mod + "_install_ansi.bas")
                [System.IO.File]::WriteAllText($ansiTemp, $utf8, $ansi)
                $vp.VBComponents.Import($ansiTemp) | Out-Null
                Remove-Item $ansiTemp -Force -ErrorAction SilentlyContinue
            }
        }

        if (Test-Path $pqDir) {
            foreach ($pqFile in (Get-ChildItem -Path $pqDir -Filter *.pq -File | Sort-Object Name)) {
                $pqName = [System.IO.Path]::GetFileNameWithoutExtension($pqFile.Name)
                $pqFormula = [System.IO.File]::ReadAllText($pqFile.FullName)
                $curQuery = $null
                try { $curQuery = $wb.Queries.Item($pqName) } catch { }
                if ($null -ne $curQuery) {
                    $curQuery.Formula = $pqFormula
                    Write-Output ("PQ_DIFF " + $pqName + " - запрос существует, обновлён из исходника")
                } else {
                    $wb.Queries.Add($pqName, $pqFormula) | Out-Null
                    Write-Output ("PQ_ADDED " + $pqName + " - запроса не было, добавлен из исходника")
                }
            }
        }

        $wb.Save()
        Write-Output "BUILD_SAVED"
    } finally {
        try { $wb.Close($false) } catch { }
    }
} catch {
    Write-Output ("BUILD_ERROR " + $_.Exception.Message)
    $excel.Quit()
    [System.Runtime.InteropServices.Marshal]::ReleaseComObject($excel) | Out-Null
    exit 1
}
$excel.Quit()
[System.Runtime.InteropServices.Marshal]::ReleaseComObject($excel) | Out-Null
Write-Output "BUILD_OK"
exit 0

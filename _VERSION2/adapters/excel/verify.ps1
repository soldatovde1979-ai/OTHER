# verify.ps1 — проверка книги (Excel-адаптер)
#
# Контракт (spec-version-contract.md): успех = код 0, сбой = ненулевой.
# Принудительная компиляция VBA: копия книги в %TEMP%, открытие через COM и
# запуск публичной функции-зонда — VBA компилирует весь проект перед первым
# вызовом, поэтому ошибка компиляции всплывает здесь, не трогая оригинал.
#
# ТОЧКА АДАПТАЦИИ: $CompileProbe — имя публичной функции для запуска
# (например, "HasColumn"). Пусто = компиляция не проверяется, VERIFY_SKIP.
# Watchdog убивает ТОЛЬКО EXCEL-процессы, запущенные этим скриптом.
# UTF-8 с BOM: PowerShell 5.1 иначе читает кириллицу как ANSI.

param(
    [string]$Target
)

$ErrorActionPreference = "Stop"
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

# ТОЧКА АДАПТАЦИИ: публичная функция-зонд компиляции.
$CompileProbe = ""

if ($Target -eq "") { Write-Output "VERIFY_ERROR - не задан -Target"; exit 1 }
$full = $Target
if (-not [System.IO.Path]::IsPathRooted($full)) { $full = [System.IO.Path]::GetFullPath($Target) }
if (-not (Test-Path -LiteralPath $full)) { Write-Output ("VERIFY_ERROR - файл не найден: " + $full); exit 1 }

if ($CompileProbe -eq "") {
    Write-Output "VERIFY_SKIP - функция-зонд не задана, компиляция не проверяется"
    exit 0
}

$tmp = Join-Path $env:TEMP ("v2_compile_check_" + [System.IO.Path]::GetFileName($full))
Copy-Item $full $tmp -Force

$before = @(Get-Process EXCEL -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Id)
$job = Start-Job -ScriptBlock {
    param($sec, $ids)
    Start-Sleep -Seconds $sec
    foreach ($p in Get-Process EXCEL -ErrorAction SilentlyContinue) {
        if ($ids -notcontains $p.Id) { Stop-Process -Id $p.Id -Force -ErrorAction SilentlyContinue }
    }
} -ArgumentList 120, $before

$excel = New-Object -ComObject Excel.Application
$excel.Visible = $false
$excel.DisplayAlerts = $false
$failed = $false
try {
    $wb = $excel.Workbooks.Open($tmp, 0, $false)
    try {
        $res = $excel.Run($CompileProbe, "x")
        Write-Output ("VERIFY_OK " + $full + " - зонд " + $CompileProbe + " вернул " + $res)
    } catch {
        Write-Output ("VERIFY_FAIL " + $full + " - " + $_.Exception.Message)
        $failed = $true
    }
    try { $wb.Close($false) } catch { }
} catch {
    Write-Output ("VERIFY_FAIL " + $full + " - " + $_.Exception.Message)
    $failed = $true
}
$excel.Quit()
[System.Runtime.InteropServices.Marshal]::ReleaseComObject($excel) | Out-Null
Stop-Job $job -ErrorAction SilentlyContinue
Remove-Job $job -Force -ErrorAction SilentlyContinue
Remove-Item $tmp -Force -ErrorAction SilentlyContinue
if ($failed) { exit 1 }
exit 0

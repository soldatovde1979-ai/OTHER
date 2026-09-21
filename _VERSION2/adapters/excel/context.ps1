# context.ps1 — контекст артефакта для миграций (Excel-адаптер)
#
# Контракт (spec-version-contract.md): открыть книгу, выполнить миграцию в
# своём процессе (чтобы COM-объект книги был доступен миграции), сохранить и
# закрыть. Миграция НЕ сохраняет и НЕ закрывает книгу сама.
#
# Миграция получает: -Workbook (открытая книга) и -BookPath (полный путь).
#
# Usage: powershell -File context.ps1 -Target <книга> -Migration <путь.ps1>
# UTF-8 с BOM: PowerShell 5.1 иначе читает кириллицу как ANSI.

param(
    [string]$Target,
    [string]$Migration
)

$ErrorActionPreference = "Stop"
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

if ($Migration -eq "") { Write-Output "CONTEXT_SKIP - миграция не задана"; exit 0 }
if (-not (Test-Path -LiteralPath $Migration)) { Write-Output ("MIGRATION_NOT_FOUND " + $Migration); exit 1 }

$full = $Target
if (-not [System.IO.Path]::IsPathRooted($full)) { $full = [System.IO.Path]::GetFullPath($Target) }
if (-not (Test-Path -LiteralPath $full)) { Write-Output ("CONTEXT_ERROR - файл не найден: " + $full); exit 1 }

$excel = New-Object -ComObject Excel.Application
$excel.Visible = $false
$excel.DisplayAlerts = $false
try {
    $wb = $excel.Workbooks.Open($full, 0, $false)
    try {
        Write-Output ("CONTEXT_OPEN " + $full)
        & $Migration -Workbook $wb -BookPath $full | ForEach-Object { Write-Output ("MIG " + $_) }
        if ($LASTEXITCODE -ne 0 -and $LASTEXITCODE -ne $null) {
            throw ("миграция вернула код " + $LASTEXITCODE)
        }
        $wb.Save()
        Write-Output "CONTEXT_SAVED"
    } finally {
        try { $wb.Close($false) } catch { }
    }
} catch {
    Write-Output ("CONTEXT_ERROR " + $_.Exception.Message)
    $excel.Quit()
    [System.Runtime.InteropServices.Marshal]::ReleaseComObject($excel) | Out-Null
    exit 1
}
$excel.Quit()
[System.Runtime.InteropServices.Marshal]::ReleaseComObject($excel) | Out-Null
exit 0

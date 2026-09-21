# stamp.ps1 — штамп версии в CustomDocumentProperties книги (Excel-адаптер)
#
# Контракт (spec-version-contract.md):
#   -Read: напечатать STAMP_VERSION / STAMP_DATE / STAMP_MD5 / STAMP_RELEASE_NO.
#          Отсутствующее свойство = пусто / 0.
#   Запись: -Version -Date -Md5 -ReleaseNo — открыть книгу, записать свойства,
#          сохранить и закрыть. Успех = код 0 и STAMP_WRITTEN.
#
# Свойства видны в «Свойствах файла» проводника.
# UTF-8 с BOM: PowerShell 5.1 иначе читает кириллицу как ANSI.

param(
    [string]$Target,
    [switch]$Read,
    [string]$Version = "",
    [string]$Date = "",
    [string]$Md5 = "",
    [int]$ReleaseNo = 0
)

$ErrorActionPreference = "Stop"
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

if ($Target -eq "") { Write-Output "STAMP_ERROR - не задан -Target"; exit 1 }
$full = $Target
if (-not [System.IO.Path]::IsPathRooted($full)) { $full = [System.IO.Path]::GetFullPath($Target) }
if (-not (Test-Path -LiteralPath $full)) { Write-Output "STAMP_ERROR - файл не найден: $full"; exit 1 }

function Set-BookProperty($wb, [string]$name, [string]$value) {
    $props = $wb.CustomDocumentProperties
    try {
        $props.Item($name).Value = $value
    } catch {
        # 4 = msoPropertyTypeString; $false = не связать со значением ячейки
        $props.Add($name, $false, 4, $value) | Out-Null
    }
}

$excel = New-Object -ComObject Excel.Application
$excel.Visible = $false
$excel.DisplayAlerts = $false
try {
    if ($Read) {
        $wb = $excel.Workbooks.Open($full, 0, $true)
        try {
            $v = ""; $d = ""; $m = ""; $rn = 0
            foreach ($p in $wb.CustomDocumentProperties) {
                switch ([string]$p.Name) {
                    "BuildVersion"   { $v = [string]$p.Value }
                    "BuildDate"      { $d = [string]$p.Value }
                    "BuildSrcMd5"    { $m = [string]$p.Value }
                    "BuildReleaseNo" { $rn = [int]$p.Value }
                }
            }
            Write-Output ("STAMP_VERSION " + $v)
            Write-Output ("STAMP_DATE " + $d)
            Write-Output ("STAMP_MD5 " + $m)
            Write-Output ("STAMP_RELEASE_NO " + $rn)
        } finally {
            try { $wb.Close($false) } catch { }
        }
    } else {
        $wb = $excel.Workbooks.Open($full, 0, $false)
        try {
            Set-BookProperty $wb "BuildVersion" $Version
            Set-BookProperty $wb "BuildDate" $Date
            Set-BookProperty $wb "BuildSrcMd5" $Md5
            Set-BookProperty $wb "BuildReleaseNo" ("" + $ReleaseNo)
            $wb.Save()
            Write-Output ("STAMP_WRITTEN " + $Version + " (" + $ReleaseNo + ")")
        } finally {
            try { $wb.Close($false) } catch { }
        }
    }
} catch {
    Write-Output ("STAMP_ERROR " + $_.Exception.Message)
    $excel.Quit()
    [System.Runtime.InteropServices.Marshal]::ReleaseComObject($excel) | Out-Null
    exit 1
}
$excel.Quit()
[System.Runtime.InteropServices.Marshal]::ReleaseComObject($excel) | Out-Null
exit 0

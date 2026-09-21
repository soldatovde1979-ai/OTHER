# install_prod.ps1
#
# Прод-обёртка: запускает install.ps1 (ядро) против прод-цели.
# Своей логики версионирования не имеет — только цель и прозрачный итог.
#
# Usage:
#   powershell -NoProfile -ExecutionPolicy Bypass -File install\install_prod.ps1
#   powershell ... -Target ".\МойАртефакт.xlsm"
#
# UTF-8 with BOM: required by PowerShell 5.1 for the Russian messages below.

param(
    [string]$Target = ".\<ПУТЬ_К_ПРОД_АРТЕФАКТУ>"
)

[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$scriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$install = Join-Path $scriptRoot "install.ps1"

$fullTarget = $Target
if (-not [System.IO.Path]::IsPathRooted($fullTarget)) {
    $projectRoot = Split-Path -Parent $scriptRoot
    $fullTarget = Join-Path $projectRoot $fullTarget
}
$fullTarget = [System.IO.Path]::GetFullPath($fullTarget)

Write-Output "PROD_TARGET $fullTarget - цель установки (полный путь)"
Write-Output "RUNNING $install - запуск ядра"
& powershell -NoProfile -ExecutionPolicy Bypass -File $install -Target "$fullTarget"
$code = $LASTEXITCODE
Write-Output "INSTALL_EXIT $code - код возврата ядра"
if ($code -eq 0) { Write-Output "PROD_OK - релиз выполнен и подтверждён" } else { Write-Output "PROD_FAIL - релиз прерван, см. RELEASE_FAIL выше" }
exit $code

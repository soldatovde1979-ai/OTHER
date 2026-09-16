# install_prod.ps1 — универсальная надстройка над install (шаблон)
#
# Роль: «install с ключами продуктива». Надстройка над install.ps1
# (объединение install + release): запускает его против прод-цели и
# возвращает код результата. Установка, версия, миграции и журнал — внутри
# install.ps1; сюда ходят, когда нужен прогон именно по прод-цели.
#
# ТОЧКИ АДАПТАЦИИ: прод-цель по умолчанию.
#
# Использование:
#   powershell -NoProfile -ExecutionPolicy Bypass -File install\install_prod.ps1
#   powershell -NoProfile -ExecutionPolicy Bypass -File install\install_prod.ps1 -Target ".\<артефакт>"
#
# Файл обязательно UTF-8 с BOM: PowerShell 5.1 иначе читает кириллицу как ANSI.

param(
    # ТОЧКА АДАПТАЦИИ: прод-цель по умолчанию (файл артефакта или каталог).
    # Относительный путь резолвится от корня проекта (папки выше папки скрипта).
    [string]$Target = ".\<ПУТЬ_К_АРТЕФАКТУ>"
)

$ErrorActionPreference = "Stop"
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

$scriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$projectRoot = Split-Path -Parent $scriptRoot
$install = Join-Path $scriptRoot "install.ps1"

# Разрешаем цель так же, как это делает install.ps1, и печатаем полный путь,
# чтобы в выводе было однозначно видно, какой файл будет обработан.
$fullTarget = $Target
if (-not [System.IO.Path]::IsPathRooted($fullTarget)) {
    $fullTarget = Join-Path $projectRoot $fullTarget
}
$fullTarget = [System.IO.Path]::GetFullPath($fullTarget)

Write-Output "PROD_TARGET $fullTarget - прод-цель (полный путь)"
Write-Output "RUNNING $install - запуск install.ps1 с ключами продуктива"
& powershell -NoProfile -ExecutionPolicy Bypass -File $install -Target "$fullTarget"
$code = $LASTEXITCODE
Write-Output "INSTALL_EXIT $code - код возврата install.ps1"
if ($code -eq 0) { Write-Output "PROD_OK - установка выполнена, версия зафиксирована" } else { Write-Output "PROD_FAIL - установка не прошла, смотрите строки выше" }
exit $code

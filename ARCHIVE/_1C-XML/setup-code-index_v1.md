# Установка индекса метаданных 1С (code-index-mcp, сборка bsl-indexer): инструкция для ИИ-агента

VERSION = 1.0
Агент: Roo Code в VS Code. ОС: Windows. Оболочка: PowerShell 5.1+. Права администратора не нужны.
Источник фактов: github.com/Regsorm/code-index-mcp, файлы `docs/manual-install.md`, `docs/bsl-indexer.md`, `install.ps1`.
Проверено 19.10.2026 по документации. Сам инструмент на этой конфигурации не запускался.

Цель: скачать, установить и запустить индексатор и MCP-сервер, построить индекс выгрузки ERP и подключить его к Roo. В конце выдать отчёт «ГОТОВО» (раздел 4).

---

## 0. Параметры (заполняет или подтверждает человек до запуска)

| Параметр | Значение | Комментарий |
|---|---|---|
| `TAG` | `1.12.0` | Версия выпуска фиксируется явно, чтобы установка была воспроизводимой |
| `INSTALL_DIR` | `C:\tools\code-index` | Папка программы, в ней же `CODE_INDEX_HOME` |
| `DUMP_DIR` | `C:\Projects\1C_ERP\CONFIGs\ERP` | Выгрузка Конфигуратора, в корне должен лежать `Configuration.xml` |
| `ALIAS` | `erp` | Короткое имя репозитория, агент указывает его в каждом вызове инструментов |
| `MCP_PORT` | `8011` | Порт MCP-сервера |
| `DAEMON_PORT` | `8015` | Порт индексатора |
| `WORKSPACE_ROOT` | `<?>` | Корень папки, открытой в VS Code. Туда кладётся `.roo\mcp.json`. Если не задан, STOP и спросить |
| `ZIP_LOCAL` | пусто | Пусто: качать с GitHub. Иначе полный путь к заранее скачанному `bsl-indexer-windows-x64.zip` |
| `AUTOSTART` | `нет` | `да`: запускать индексатор и сервер при входе в Windows (через папку автозагрузки) |
| `INDEX_TIMEOUT_MIN` | `90` | Сколько минут максимум ждать первую индексацию |

---

## 1. Правила для агента

1. Шаги выполняются строго по порядку. Каждый шаг устроен так: команда, затем проверка, затем строка в журнал отчёта.
2. **STOP** означает: остановиться, показать человеку, что именно увидел (вывод команды), предложить варианты и ждать ответа. Обходить STOP другим способом запрещено.
3. Чего не делать:
   - не запускать `irm ... | iex` и никакие скачанные скрипты, используется только готовый `.exe` из архива выпуска;
   - не менять файлы выгрузки (индексатор сам создаст в `DUMP_DIR` папку `.code-index`, и это ожидаемо);
   - не трогать `.roo\rules\*`, `.gitignore`, git, PATH, системные настройки, Планировщик заданий;
   - не запускаться от имени администратора.
4. Все команды выполняются в PowerShell в терминале VS Code на **этой** машине. Перед каждым блоком команд выставляется `$ErrorActionPreference = 'Stop'`.
5. Повторный запуск инструкции безопасен: каждый шаг сначала проверяет, сделан ли он уже.

---

## 2. Шаги

### Шаг 1. Убедиться, на какой машине идёт работа

```powershell
$ErrorActionPreference = 'Stop'
"Машина: $env:COMPUTERNAME | Пользователь: $(whoami) | Сеанс: $env:SESSIONNAME"
"PowerShell: $($PSVersionTable.PSVersion)"
"Текущая папка: $((Get-Location).Path)"
```

Что делает: печатает имя компьютера, пользователя, тип сеанса, версию PowerShell и текущую папку.

- `$env:SESSIONNAME`: `Console` означает локальный вход, `RDP-Tcp#N` означает удалённый рабочий стол.

**STOP**, если сеанс `RDP-Tcp*`. Это может быть общий сервер или ферма RDS, и ставить туда фоновые процессы можно только с явного разрешения человека.

### Шаг 2. Предпроверки (ничего не меняют)

```powershell
$ErrorActionPreference = 'Stop'
$TAG='1.12.0'; $INSTALL_DIR='C:\tools\code-index'; $DUMP_DIR='C:\Projects\1C_ERP\CONFIGs\ERP'
$MCP_PORT=8011; $DAEMON_PORT=8015
$exe = Join-Path $INSTALL_DIR 'bsl-indexer.exe'

# 2.1 Выгрузка на месте
Test-Path -LiteralPath (Join-Path $DUMP_DIR 'Configuration.xml')

# 2.2 Свободное место на диске выгрузки и диске установки
Get-PSDrive -Name ($DUMP_DIR.Substring(0,1)), ($INSTALL_DIR.Substring(0,1)) |
  Select-Object Name, @{n='СвободноГБ';e={[math]::Round($_.Free/1GB,1)}}

# 2.3 Порты не заняты чужими программами
Get-NetTCPConnection -LocalPort $MCP_PORT,$DAEMON_PORT -State Listen -ErrorAction SilentlyContinue |
  Select-Object LocalPort, OwningProcess, @{n='Процесс';e={(Get-Process -Id $_.OwningProcess).ProcessName}}

# 2.4 Нет ли уже установки
"exe есть: $(Test-Path -LiteralPath $exe)"
"CODE_INDEX_HOME (User): $([Environment]::GetEnvironmentVariable('CODE_INDEX_HOME','User'))"
Get-Process bsl-indexer -ErrorAction SilentlyContinue | Select-Object Id, StartTime

# 2.5 Лежит ли выгрузка под git
"git в выгрузке: $(Test-Path -LiteralPath (Join-Path $DUMP_DIR '.git'))"

# 2.6 Объём выгрузки (для оценки времени индексации)
"Файлов в выгрузке: $((Get-ChildItem -LiteralPath $DUMP_DIR -Recurse -File).Count)"
```

Что делает: только читает состояние системы.

- `Test-Path` проверяет, существует ли файл или папка.
- `Get-PSDrive` показывает свободное место на дисках.
- `Get-NetTCPConnection -State Listen` показывает, кто слушает порты 8011 и 8015.
- `GetEnvironmentVariable(...,'User')` читает переменную окружения пользователя.
- `Get-ChildItem -Recurse -File` считает файлы и может занять до минуты.

Ожидается, а в противном случае **STOP**:

- 2.1 вернул `True`. Если `False`, выгрузки нет по этому пути.
- 2.3 пусто или процесс `bsl-indexer`. Если там чужая программа, нужно выбрать другие порты.
- 2.4: если `CODE_INDEX_HOME` уже задан и отличается от `INSTALL_DIR`, где-то есть другая установка.
- 2.4: если exe есть и процессы `bsl-indexer` работают, установка уже была. Тогда шаги 3–5 пропускаются, проверяется версия (`& $exe --version`) и работа идёт с шага 6.
- 2.5 `True`: не STOP, но в отчёт записывается «добавить `.code-index/` в `.gitignore`». Агент сам не правит.

### Шаг 3. Скачать архив выпуска

Шаг пропускается, если задан `ZIP_LOCAL`. Тогда `$zip = <ZIP_LOCAL>`, сразу шаг 4.

```powershell
$ErrorActionPreference = 'Stop'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
$rel = Invoke-RestMethod "https://api.github.com/repos/Regsorm/code-index-mcp/releases/tags/v$TAG" -Headers @{ 'User-Agent' = 'code-index-setup' }
$rel.assets | Select-Object name, size
$url = ($rel.assets | Where-Object name -eq 'bsl-indexer-windows-x64.zip').browser_download_url
$zip = Join-Path $env:TEMP 'bsl-indexer-windows-x64.zip'
Invoke-WebRequest -Uri $url -OutFile $zip -UseBasicParsing
Get-FileHash -LiteralPath $zip -Algorithm SHA256
```

Что делает: получает описание выпуска `v1.12.0` через API GitHub и скачивает архив сборки с поддержкой 1С во временную папку.

- `SecurityProtocol = Tls12` включает TLS 1.2. Без него PowerShell 5.1 может не достучаться до GitHub.
- `Invoke-RestMethod ... releases/tags/v$TAG` возвращает список файлов выпуска.
- `-Headers User-Agent`: API GitHub требует заголовок `User-Agent`.
- `Where-Object name -eq 'bsl-indexer-windows-x64.zip'` выбирает сборку с 1С. Сборка `code-index-*` без 1С не подходит.
- `-UseBasicParsing` скачивает без движка Internet Explorer.
- `Get-FileHash` считает SHA256 архива для отчёта.

Проверка: если в списке файлов выпуска есть файл контрольных сумм (`*.sha256`, `checksums*`), агент сверяет SHA256 и при несовпадении делает **STOP**.

**STOP** при сетевой ошибке. Человеку нужно скачать архив вручную со страницы `https://github.com/Regsorm/code-index-mcp/releases/tag/v1.12.0`, положить на диск и задать `ZIP_LOCAL`.

### Шаг 4. Распаковать и проверить запуск

```powershell
$ErrorActionPreference = 'Stop'
New-Item -ItemType Directory -Force -Path $INSTALL_DIR | Out-Null
Expand-Archive -LiteralPath $zip -DestinationPath $INSTALL_DIR -Force
& $exe --version
```

Что делает: создаёт папку программы, распаковывает в неё `bsl-indexer.exe` и печатает версию.

- `-Force` у `New-Item` не падает, если папка уже есть.
- `-Force` у `Expand-Archive` перезаписывает файлы. ⚠ Работающий exe перезаписать нельзя: если процессы `bsl-indexer` запущены, сначала остановить их (раздел 5, пункты 1–2).

Ожидается: вывод содержит `1.12.0`.

**STOP**, если exe не запускается. Самая частая причина: антивирус заблокировал неподписанный файл. Это решает человек.

### Шаг 5. Переменная окружения CODE_INDEX_HOME

```powershell
[Environment]::SetEnvironmentVariable('CODE_INDEX_HOME', $INSTALL_DIR, 'User')
$env:CODE_INDEX_HOME = $INSTALL_DIR
"CODE_INDEX_HOME = $([Environment]::GetEnvironmentVariable('CODE_INDEX_HOME','User'))"
```

Что делает: запоминает папку программы. Без этой переменной индексатор не запускается.

- `SetEnvironmentVariable(...,'User')` пишет переменную навсегда для текущего пользователя.
- `$env:CODE_INDEX_HOME = ...` ставит её в текущее окно, потому что новая переменная видна только в новых окнах.

⚠ Это постоянное изменение настроек пользователя. Откат описан в разделе 5.

### Шаг 6. Файл настроек daemon.toml

Важно: 1С-инструменты (`get_object_structure` и др.) появляются **только** если у пути указано `language = "bsl"`. Установщик `install.ps1` эту строку сам не пишет, поэтому файл создаётся здесь.

```powershell
$ErrorActionPreference = 'Stop'
$cfg = Join-Path $INSTALL_DIR 'daemon.toml'
$want = @"
[daemon]
http_host = "127.0.0.1"
http_port = $DAEMON_PORT
log_level = "info"

[[paths]]
path = "$($DUMP_DIR -replace '\\','/')"
alias = "erp"
language = "bsl"
"@
if (Test-Path -LiteralPath $cfg) {
    $have = [IO.File]::ReadAllText($cfg)
    if ($have.Trim() -ne $want.Trim()) { "РАЗЛИЧАЕТСЯ:"; "--- сейчас ---"; $have; "--- нужно ---"; $want }
    else { "daemon.toml уже правильный" }
} else {
    [IO.File]::WriteAllText($cfg, $want, (New-Object Text.UTF8Encoding($false)))
    "daemon.toml создан"
}
```

Что делает: создаёт файл настроек с одной папкой (выгрузка ERP, алиас `erp`, язык `bsl`). Если файл уже есть, только сравнивает.

- `-replace '\\','/'`: в файле настроек пути пишутся прямыми косыми.
- `UTF8Encoding($false)` записывает UTF-8 без BOM.
- `http_host = "127.0.0.1"`: индексатор доступен только с этой машины.

**STOP**, если вывод «РАЗЛИЧАЕТСЯ». Чужой файл настроек не перезаписывается, человек решает, объединять или нет.

### Шаг 7. Запустить индексатор и MCP-сервер (скрыто, в фоне)

Если на шаге 2.4 процессы уже работали, шаг пропускается и сразу выполняется `daemon status`.

```powershell
$ErrorActionPreference = 'Stop'
Start-Process -FilePath $exe -ArgumentList 'daemon','run' -WorkingDirectory $INSTALL_DIR -WindowStyle Hidden
Start-Sleep -Seconds 3
Start-Process -FilePath $exe -ArgumentList 'serve','--transport','http','--port',"$MCP_PORT",'--config',"`"$cfg`"" -WorkingDirectory $INSTALL_DIR -WindowStyle Hidden
Start-Sleep -Seconds 5
& $exe daemon status
```

Что делает: запускает два фоновых процесса без окон и проверяет состояние.

- `daemon run` запускает индексатор: строит индекс и следит за изменениями файлов выгрузки.
- `serve` запускает MCP-сервер, который отвечает агенту и только читает индекс.
- `--transport http` означает, что сервер постоянно слушает HTTP, один на все окна VS Code.
- `--port 8011` задаёт порт MCP-сервера.
- `--config "...daemon.toml"` обязателен: без него сервер не увидит папку и алиас `erp`.
- `-WindowStyle Hidden` прячет окна, иначе они висели бы на экране.
- `Start-Sleep 3`: по документации сервер стартует после индексатора с паузой.
- `daemon status` печатает `статус: running` и список папок.

Процессы унаследуют `CODE_INDEX_HOME` из текущего окна (шаг 5).

Ожидается: `статус: running` и строка с путём выгрузки.

**STOP**, если статус другой. Нужно показать человеку последние 40 строк журнала: `Get-Content (Join-Path $INSTALL_DIR 'daemon.log') -Tail 40`.

### Шаг 8. Дождаться первой индексации

```powershell
$deadline = (Get-Date).AddMinutes(90); $t0 = Get-Date
do {
    $st = (& $exe daemon status | Out-String)
    if ($st -match '\[ready\]') { break }
    "{0:N0} мин: идёт индексация. Журнал: {1}" -f ((Get-Date)-$t0).TotalMinutes, (Get-Content (Join-Path $INSTALL_DIR 'daemon.log') -Tail 1)
    Start-Sleep -Seconds 60
} while ((Get-Date) -lt $deadline)
$st
"Заняло минут: {0:N1}" -f ((Get-Date)-$t0).TotalMinutes
```

Что делает: раз в минуту опрашивает состояние, пока у папки не появится отметка `[ready]` (индекс построен), но не дольше 90 минут.

- `-match '\[ready\]'` ищет отметку готовности в выводе `daemon status`.
- `Get-Content -Tail 1` показывает последнюю строку журнала как индикатор прогресса.

Ориентир по документации: Бухгалтерия предприятия (88 тыс. файлов) индексировалась около 6 минут на HDD. ERP УХ больше, точного числа нет.

**STOP** по таймауту: показать `$st` и последние 40 строк `daemon.log`. Процессы не убивать.

### Шаг 9. Проверить индекс и сервер

```powershell
$db = Join-Path $DUMP_DIR '.code-index\index.db'
"index.db: {0:N0} МБ" -f ((Get-Item -LiteralPath $db).Length/1MB)
Test-NetConnection -ComputerName 127.0.0.1 -Port $MCP_PORT -InformationLevel Quiet
```

Что делает: показывает размер файла индекса и проверяет, что MCP-сервер слушает порт.

- `.code-index\index.db`: по документации индекс лежит внутри папки выгрузки.
- `Test-NetConnection -InformationLevel Quiet` возвращает просто `True` или `False`.

Ожидается: файл есть и вывод `True`. Иначе **STOP** и показать `serve.log` (`-Tail 40`).

### Шаг 10. Подключить к Roo Code (`.roo\mcp.json` проекта)

```powershell
$ErrorActionPreference = 'Stop'
$WORKSPACE_ROOT = '<?>'   # подставить из параметров; если не задан, STOP
$mcpFile = Join-Path $WORKSPACE_ROOT '.roo\mcp.json'
$entry = [pscustomobject]@{ type = 'streamable-http'; url = "http://127.0.0.1:$MCP_PORT/mcp" }
if (Test-Path -LiteralPath $mcpFile) {
    $j = Get-Content -LiteralPath $mcpFile -Raw -Encoding UTF8 | ConvertFrom-Json
    if (-not $j.mcpServers) { $j | Add-Member -NotePropertyName mcpServers -NotePropertyValue ([pscustomobject]@{}) }
    if ($j.mcpServers.'code-index') { "code-index уже есть:"; $j.mcpServers.'code-index' | ConvertTo-Json }
    else {
        $j.mcpServers | Add-Member -NotePropertyName 'code-index' -NotePropertyValue $entry
        [IO.File]::WriteAllText($mcpFile, ($j | ConvertTo-Json -Depth 20), (New-Object Text.UTF8Encoding($false)))
        "добавлен code-index в существующий $mcpFile"
    }
} else {
    New-Item -ItemType Directory -Force -Path (Split-Path $mcpFile) | Out-Null
    $j = [pscustomobject]@{ mcpServers = [pscustomobject]@{ 'code-index' = $entry } }
    [IO.File]::WriteAllText($mcpFile, ($j | ConvertTo-Json -Depth 20), (New-Object Text.UTF8Encoding($false)))
    "создан $mcpFile"
}
Get-Content -LiteralPath $mcpFile -Raw
```

Что делает: добавляет в настройки MCP проекта сервер `code-index`, не трогая уже описанные там серверы.

- `type = 'streamable-http'` обязателен: Roo без него не поймёт, как подключаться по URL.
- `url` указывает на MCP-сервер из шага 7.
- `ConvertFrom-Json` / `ConvertTo-Json -Depth 20` читают и пишут JSON. Глубина 20 нужна, чтобы PowerShell 5.1 не обрезал вложенные настройки других серверов.

**STOP**, если запись `code-index` уже есть с другим адресом: чужую запись не перезаписывать.

### Шаг 11. Автозапуск (только если `AUTOSTART = да`)

```powershell
$ErrorActionPreference = 'Stop'
$starter = Join-Path $INSTALL_DIR 'start-hidden.vbs'
@"
Set sh = CreateObject("WScript.Shell")
sh.Run Chr(34) & "$exe" & Chr(34) & " daemon run", 0, False
WScript.Sleep 3000
sh.Run Chr(34) & "$exe" & Chr(34) & " serve --transport http --port $MCP_PORT --config " & Chr(34) & "$cfg" & Chr(34), 0, False
"@ | Set-Content -LiteralPath $starter -Encoding Default
$link = Join-Path ([Environment]::GetFolderPath('Startup')) 'code-index.vbs'
@"
Set sh = CreateObject("WScript.Shell")
sh.Run Chr(34) & "$starter" & Chr(34), 0, False
"@ | Set-Content -LiteralPath $link -Encoding Default
"автозапуск: $link -> $starter"
```

Что делает: при каждом входе в Windows скрыто запускает индексатор и сервер. Схема та же, что в `install.ps1`: папка автозагрузки пользователя, без Планировщика и без прав администратора.

- `sh.Run ..., 0, False`: `0` означает без окна, `False` означает не ждать завершения.
- `-Encoding Default` пишет в ANSI, потому что `wscript` читает `.vbs` в кодировке системы.
- `GetFolderPath('Startup')` возвращает папку автозагрузки текущего пользователя.

⚠ Постоянное изменение. Откат в разделе 5.

### Шаг 12. Передать управление человеку (агент сам этого сделать не может)

Сообщить человеку дословно:

> Сервер работает. Осталось подключить его в Roo:
> 1. Панель Roo → значок MCP-серверов → включить «Enable MCP Servers», если выключено.
> 2. Там же нажать обновление списка серверов или выполнить `Developer: Reload Window` в VS Code.
> 3. У сервера `code-index` должен загореться зелёный индикатор, в списке инструментов должен появиться `get_object_structure`.
> 4. Напиши мне «подключено», и я сделаю контрольную проверку.

### Шаг 13. Контрольная проверка (после «подключено»)

1. Через MCP вызвать `health` и `get_stats` с `repo = "erp"`.
2. Через MCP вызвать `get_object_structure` для `Справочник.eamЕдиницыОборудования`. Точные имена параметров взять из схемы инструмента.
3. Сверить с XML (только чтение):
   ```powershell
   (Select-String -LiteralPath 'C:\Projects\1C_ERP\CONFIGs\ERP\Catalogs\eamЕдиницыОборудования.xml' -Pattern '<Attribute uuid').Count
   ```
   Что делает: считает реквизиты в XML, включая реквизиты табличных частей. `-Pattern` задаёт строку, с которой начинается описание реквизита.
4. Число реквизитов (шапка плюс все ТЧ) из ответа инструмента должно совпасть с числом из XML. Дополнительно сверить типы 2–3 реквизитов.
5. Вызвать `get_data_links` (или `find_references`) для того же справочника: в ответе должны быть объекты, которые на него ссылаются.

Если не совпало, это не STOP установки. Расхождение записывается в отчёт как находка: показать оба списка.

---

## 3. Типовые ошибки (по документации)

| Признак | Причина и действие |
|---|---|
| `CODE_INDEX_HOME не задана` | Шаг 5 не выполнен, или процесс запущен из старого окна. Повторить шаг 5, затем шаг 7 из того же окна |
| Ответ `daemon_offline` | Индексатор не запущен или у процессов разный `CODE_INDEX_HOME`. Выполнить `daemon status`, при необходимости шаг 7 |
| Ответ `not_started` «путь не отслеживается» | Пути нет в `daemon.toml`. Исправить файл, затем `& $exe daemon reload` |
| Ответ `unknown_repo` | Агент передал неверный алиас. Правильный: `erp` |
| `os error 10048` | Порт занят. STOP, человек выбирает другой порт, его меняют в `daemon.toml` / `serve` / `mcp.json` |
| Нет 1С-инструментов | Нет `language = "bsl"` в `daemon.toml` (шаг 6). Исправить, `daemon reload`, переподключить сервер в Roo |
| Нет `[ready]` | Идёт первая индексация, ход виден в `daemon.log` |

---

## 4. Отчёт «ГОТОВО» (формат ответа агента)

```
ГОТОВО / НЕ ГОТОВО (остановился на шаге N)

Машина / пользователь / сеанс: ...
Версия bsl-indexer: ...           SHA256 архива: ...
Программа: C:\tools\code-index
Выгрузка: C:\Projects\1C_ERP\CONFIGs\ERP   алиас: erp   файлов: ...
Индекс: ...\.code-index\index.db  размер: ... МБ   индексация заняла: ... мин
Порты: MCP 8011 (слушает: да/нет), индексатор 8015
Roo: <путь>\.roo\mcp.json (создан / дополнен / уже был)
Автозапуск: да/нет
Контрольная проверка (шаг 13): совпало / расхождения: ...

Что изменено в системе:
- переменная пользователя CODE_INDEX_HOME
- папка C:\tools\code-index
- папка .code-index внутри выгрузки
- .roo\mcp.json
- (если да) автозагрузка: code-index.vbs

Требует внимания человека:
- (если выгрузка под git) добавить .code-index/ в .gitignore
- в проекте есть старое правило .roo\rules\1c-metadata-index.md (индекс tsv). Решить: оставить, переписать или отключить
- STOP-ы и находки: ...
```

---

## 5. Откат (выполнять только по команде человека)

1. `& 'C:\tools\code-index\bsl-indexer.exe' daemon stop` останавливает индексатор.
2. `Stop-Process -Name bsl-indexer` останавливает MCP-сервер. ⚠ Завершает **все** процессы с этим именем.
3. Удалить `code-index.vbs` из папки `[Environment]::GetFolderPath('Startup')`, если автозапуск ставился.
4. `[Environment]::SetEnvironmentVariable('CODE_INDEX_HOME', $null, 'User')` удаляет переменную.
5. ⚠ Удалить папку `C:\tools\code-index` и папку `C:\Projects\1C_ERP\CONFIGs\ERP\.code-index`. Это необратимо, перед удалением показать человеку содержимое и получить подтверждение.
6. Удалить ключ `code-index` из `.roo\mcp.json`.

## 6. После новой выгрузки конфигурации

Индексатор сам следит за изменениями файлов. После полной перевыгрузки выполнить `daemon status` и дождаться `[ready]`. Если после обновления версии программы индекс ведёт себя странно, документация предписывает разовую полную переиндексацию: `bsl-indexer index <путь> --force`.

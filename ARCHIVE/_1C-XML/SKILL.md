---
name: 1c-add-config
description: Подключает новую XML-выгрузку конфигурации или расширения 1С к уже установленному индексу code-index (bsl-indexer). Добавляет папку в daemon.toml, перечитывает настройки, ждёт построения индекса, проверяет и отчитывается. Используй, когда просят «подключи / добавь / проиндексируй конфигурацию (выгрузку) в папке X», а также чтобы отключить конфигурацию от индекса. Не используй для первичной установки code-index (для неё есть setup-code-index_v1.md) и для вопросов о структуре 1С (для них правило 1c-code-index).
---

# Подключение конфигурации 1С к индексу code-index

VERSION = 1.0 · bsl-indexer 1.12.0 · Windows, PowerShell 5.1 · без прав администратора
Источник: github.com/Regsorm/code-index-mcp, файлы docs/manual-install.md и docs/bsl-indexer.md.

## Входные данные (спросить у человека, если не названы)
- `NEW_PATH`: папка выгрузки. В её корне должен лежать `Configuration.xml`.
- `NEW_ALIAS`: короткое имя латиницей в нижнем регистре (`ut`, `zup`, `erp_test`). Агент указывает его в вызовах инструментов как `repo`.
- `DESCR`: одна строка «что это за база» для отчёта и правила.

Если чего-то не хватает, спроси один раз всё сразу, а не по одному вопросу.

## Правила
- STOP означает: остановиться, показать вывод, предложить варианты и ждать решения человека.
- Меняется только `C:\tools\code-index\daemon.toml`, и только после того, как сделана копия. Выгрузку, `.roo\mcp.json` и правила не трогать.
- Порядок шагов не менять. Повторный запуск безопасен: если папка уже подключена, перейти к шагу 5.

## Шаг 1. Проверки (ничего не меняют)
```powershell
$ErrorActionPreference = 'Stop'
$INSTALL_DIR = $env:CODE_INDEX_HOME; if (-not $INSTALL_DIR) { $INSTALL_DIR = 'C:\tools\code-index' }
$exe = Join-Path $INSTALL_DIR 'bsl-indexer.exe'; $cfg = Join-Path $INSTALL_DIR 'daemon.toml'
$NEW_PATH = '<путь>'; $NEW_ALIAS = '<алиас>'
$p = ($NEW_PATH.TrimEnd('\') -replace '\\','/')
"Configuration.xml: $(Test-Path -LiteralPath (Join-Path $NEW_PATH 'Configuration.xml'))"
$toml = [IO.File]::ReadAllText($cfg)
"Путь уже в конфиге: $($toml -match ('(?im)^\s*path\s*=\s*\"' + [regex]::Escape($p) + '/?\"'))"
"Алиас уже занят: $($toml -match ('(?m)^\s*alias\s*=\s*\"' + [regex]::Escape($NEW_ALIAS) + '\"'))"
"Файлов в выгрузке: $((Get-ChildItem -LiteralPath $NEW_PATH -Recurse -File).Count)"
& $exe daemon status
```

Что делает: проверяет выгрузку, ищет путь и алиас среди уже подключённых, считает файлы, показывает состояние индексатора.

- `$env:CODE_INDEX_HOME` — папка программы. Если переменная не задана, берётся путь по умолчанию.
- `-replace '\\','/'`: в `daemon.toml` пути пишутся прямыми косыми.
- `(?im)`: поиск без учёта регистра, построчно.
- `[regex]::Escape` экранирует спецсимволы пути.
- `daemon status` печатает статус индексатора и список папок.

STOP, если:
- `Configuration.xml: False` — это не выгрузка Конфигуратора;
- индексатор не `running` — сначала поднять его по setup-code-index_v1.md, шаг 7;
- алиас занят другой папкой — человек выбирает другой.

Если путь уже есть в конфиге, перейти к шагу 5.

## Шаг 2. Копия daemon.toml
```powershell
$bak = "$cfg.bak-$(Get-Date -Format yyyyMMdd-HHmmss)"
Copy-Item -LiteralPath $cfg -Destination $bak
"копия: $bak"
```

Что делает: сохраняет текущий файл настроек с меткой времени, чтобы можно было вернуть как было.

## Шаг 3. Добавить секцию
```powershell
$section = @"

[[paths]]
path = "$p"
alias = "$NEW_ALIAS"
language = "bsl"
"@
[IO.File]::WriteAllText($cfg, $toml.TrimEnd() + "`r`n" + $section + "`r`n", (New-Object Text.UTF8Encoding($false)))
[IO.File]::ReadAllText($cfg)
```

Что делает: дописывает в конец `daemon.toml` новую папку. Существующие секции не меняются.

- `language = "bsl"` обязателен: без него для этой папки не будет 1С-инструментов.
- `UTF8Encoding($false)` пишет UTF-8 без BOM.

## Шаг 4. Перечитать настройки
```powershell
& $exe daemon reload
Start-Sleep -Seconds 5
& $exe daemon status
```

Что делает: индексатор перечитывает `daemon.toml` без перезапуска и начинает индексировать новую папку.

- `daemon reload` — штатная команда из документации для добавленных путей.

MCP-сервер (`serve --config`) сам замечает изменения файла. Переподключать его в Roo не нужно, потому что 1С-инструменты уже включены.

STOP, если в `daemon status` нет новой папки. Показать `Get-Content (Join-Path $INSTALL_DIR 'daemon.log') -Tail 40` и откатиться (раздел «Откат»).

## Шаг 5. Дождаться индекса (до 90 минут)
```powershell
$deadline = (Get-Date).AddMinutes(90); $t0 = Get-Date
$leaf = Split-Path $NEW_PATH.TrimEnd('\') -Leaf
do {
    $line = (& $exe daemon status) | Where-Object { $_ -match [regex]::Escape($leaf) }
    if ($line -match '\[ready\]') { break }
    "{0:N0} мин: {1}" -f ((Get-Date)-$t0).TotalMinutes, ($line -join ' ')
    Start-Sleep -Seconds 60
} while ((Get-Date) -lt $deadline)
$line
"Индекс: {0:N0} МБ" -f ((Get-Item -LiteralPath (Join-Path $NEW_PATH '.code-index\index.db')).Length/1MB)
```

Что делает: раз в минуту смотрит строку новой папки в `daemon status`, пока на ней не появится `[ready]`.

- `Split-Path -Leaf` берёт имя последней папки, по нему ищется нужная строка.
- `.code-index\index.db` — сам индекс, он лежит внутри выгрузки.

STOP по таймауту: показать строку статуса и хвост `daemon.log`. Процессы не трогать.

## Шаг 6. Проверка через MCP
1. `get_stats` с `repo = NEW_ALIAS` должен ответить без ошибки.
2. Взять любой справочник из `NEW_PATH\Catalogs\` и вызвать для него `get_object_structure`.
3. Посчитать реквизиты в XML этого справочника:
   ```powershell
   (Select-String -LiteralPath '<NEW_PATH>\Catalogs\<Имя>.xml' -Pattern '<Attribute uuid').Count
   ```
   Что делает: считает реквизиты в XML, включая реквизиты табличных частей.
4. Число из XML должно совпасть с числом реквизитов (шапка плюс ТЧ) в ответе инструмента. Расхождение — не STOP, а находка для отчёта.

Если `unknown_repo`, подождать 10 секунд и повторить один раз. Если ошибка осталась, STOP: сервер не подхватил настройки, человеку нужно переподключить `code-index` в панели MCP Roo.

## Отчёт
```
ПОДКЛЮЧЕНО / НЕ ПОДКЛЮЧЕНО (шаг N)
Алиас: ...   Папка: ...   Описание: ...
Файлов: ...   Индекс: ... МБ   Индексация: ... мин
Проверка: справочник ..., реквизитов XML ... / индекс ... — совпало / нет
Изменено: daemon.toml (копия: ...)
Человеку: добавить строку «<алиас> — <описание>» в правило 1c-code-index, иначе агент будет ходить только в erp.
          Если выгрузка под git — добавить .code-index/ в .gitignore.
```

## Отключение конфигурации (только по команде человека)
1. Сделать копию `daemon.toml`, как в шаге 2.
2. Удалить из файла секцию `[[paths]]` с этим алиасом, показав её человеку перед удалением.
3. Выполнить `& $exe daemon reload`, затем `daemon status` и убедиться, что папки больше нет в списке.
4. ⚠ Папку `<путь>\.code-index` удалять только по отдельному подтверждению: это необратимо.

## Откат добавления
```powershell
Copy-Item -LiteralPath $bak -Destination $cfg -Force; & $exe daemon reload
```

Что делает: возвращает файл настроек из копии и перечитывает его. `-Force` перезаписывает текущий файл.

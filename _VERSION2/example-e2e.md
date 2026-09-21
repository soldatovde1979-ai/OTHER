# example-e2e — сквозной пример версионирования на основе ReportMTO

Показывает механизм [`_VERSION2`](readme.md) по шагам: от переноса в проект до
двух релизов. Взят реальный проект ReportMTO (Excel-книга с макросами).
Формат таблиц: `номер шага | входные данные | название шага | описание шага |
выходные данные | следующий номер шага` — уровень детализации вплоть до
модуля, как требует владелец.

## 1. Входные данные: ответы опросника (ReportMTO)

| № вопроса (spec-version-onboard) | Ответ для ReportMTO |
|---|---|
| 1. Проект | `ReportMTO`, корень `C:\Projects\ReportMTO` |
| 2. Продуктив | книга `.\ReportMTO.xlsm` в корне проекта; рабочие копии на Google Диске; в git книга не входит |
| 3. Исходники | `src\vba\*.bas` (11 модулей), `src\powerquery\*.pq` (16 запросов), `tmp_index.html`, документация (`README.md`, `docs\**\*.md`, `install\*.md`) |
| 4. Штамп | `CustomDocumentProperties` книги: `BuildVersion`, `BuildDate`, `BuildSrcMd5`, `BuildReleaseNo` |
| 5. Сборка/проверка | адаптер `excel`: `build.ps1` (импорт `.bas`/`.pq`), `verify.ps1` (компиляция через зонд `HasColumn`); нюанс: запрос `qDiagImport.pq` в книгу не ставится, шаблон `tmp_index.html` переносится точкой адаптации |
| 6. Миграции | есть: `install\migrations\8.1.0__variable_keys.ps1` (ключ `DATA/KEEP_WEEKS=52`) |
| 7. Текущая версия | `8.1.9` (история релизов 8.1.0–8.1.9) |
| 8. Счётчик релизов | следующий номер — `10` (`$StartReleaseNo = 10`) |
| 9. Кто релизит | две машины, правило git pull → релиз → git push |
| 10. Прод-цель | `.\ReportMTO.xlsm` (для `install_prod.ps1`) |

## 2. Раскладка подсистемы в проекте после переноса

```
ReportMTO\
├── CHANGELOG.md                      ← журнал (ведёт install.ps1)
├── ReportMTO.xlsm                    ← прод-книга (не в git; штамп в свойствах файла)
├── tmp_index.html                    ← исходник: HTML-шаблон
├── src\vba\*.bas                     ← исходники: 11 модулей
├── src\powerquery\*.pq               ← исходники: 16 запросов
├── docs\**\*.md                      ← документация проекта (входит в дайджест)
└── install\
    ├── install.ps1                   ← ядро (перенесено из _VERSION2)
    ├── install_prod.ps1              ← прод-обёртка
    ├── VERSION                       ← SemVer + описание следующего релиза (описание — руками)
    ├── release.state                 ← хеши и release_no (ведёт install.ps1)
    ├── build-info.json               ← манифест релиза (ведёт install.ps1)
    ├── migrations\
    │   └── 8.1.0__variable_keys.ps1
    └── adapter\                      ← файлы адаптера excel
        ├── build.ps1
        ├── verify.ps1
        ├── stamp.ps1
        └── context.ps1
```

Гайды (`spec-*.md`, `doc-version.md`, этот пример) в проект не переносятся —
они остаются в `_VERSION2`.

## 3. Релиз 8.1.10 (10) — сквозной проход по шагам

Запуск: `powershell -NoProfile -ExecutionPolicy Bypass -File install\install.ps1`

| Номер шага | Входные данные | Название шага | Описание шага | Выходные данные | Следующий номер шага |
|---|---|---|---|---|---|
| 1 | человек, `install\VERSION` | Заполнение описания | Владелец вписывает ниже первой строки VERSION человеческое описание: «Исправлена ошибка … (какая), добавлен блок …, оптимизирован … (результат)» | описание в VERSION | 2 |
| 2 | `-Target`, `-Bump`, `-DryRun`, `-Force`, `-AdapterDir` | Разбор параметров | Ядро принимает параметры; `-Bump` по умолчанию `patch`; `$AdapterDir = install\adapter` | значения параметров | 3 |
| 3 | `$ProjectName="ReportMTO"`, `$SourceItems`, `$AdapterType="excel"`, `$StartReleaseNo=10` | Проверка точек адаптации | Ядро проверяет, что имя проекта, список исходников и тип адаптера заполнены; пусто → `RELEASE_FAIL` | точки адаптации подтверждены | 4 |
| 4 | файл `install\VERSION` (первая строка `8.1.9`) | Чтение версии исходников | `Read-BuildVersion()`: первая непустая строка должна быть вида `1.2.3` | `$curVersion = "8.1.9"` | 5 |
| 5 | `install\VERSION` (строки ниже первой) | Чтение описания | `Read-VersionDescription()`: все непустые строки ниже версии собираются в массив | `$desc = @(описание)` | 5.1 |
| 5.1 | все файлы из `src\vba`, `src\powerquery`, `tmp_index.html`, `README.md`, `docs\**\*.md`, `install\*.md`; файлы из `release.state` | Сравнение хэш-сумм | `Get-SourceMap()` считает MD5 каждого файла; ядро сравнивает с хешами прошлого релиза (`release.state`, строки `file <путь> <md5>`) | список изменённых файлов; `$changedFiles` | 5.2 если есть изменения, 5.3 если нет |
| 5.2 | `$changedFiles`, `$state.Digest` | Вывод изменений | Маркер `RELEASE_SOURCES_CHANGED <n> - изменились: …`; изменён хотя бы один из `modAggregate.bas`…`modPQSync.bas`, `*.pq`, `tmp_index.html` или документов | список в выводе | 6 |
| 5.3 | `$state.Digest` (пуст) | Первый прогон? | Если `release.state` нет — маркер `RELEASE_FIRST_RUN`, версия не поднимается | `RELEASE_FIRST_RUN` | 7 |
| 6 | `$curVersion="8.1.9"`, `$Bump="patch"` | Подъём версии | `Step-Version`: патч → `8.1.10`; минор/мажор — только по флагу | `$newVersion="8.1.10"`, маркер `RELEASE_VERSION_NEXT` | 7 |
| 7 | книга `ReportMTO.xlsm` закрыта, адаптер `install\adapter\stamp.ps1 -Read` | Чтение штампа книги | Адаптер открывает книгу только для чтения и читает `CustomDocumentProperties`; ядро разбирает `STAMP_VERSION`, `STAMP_MD5` | версия и хеш, стоящие в книге до релиза | 7.1 книга старее → 8; 7.2 книга новее → `RELEASE_FAIL` (или 8 при `-Force`); 7.3 версии равны, хеш разный → `BOOK_MD5_MISMATCH`, продолжаем |
| 8 | `$fullTarget`, `$root` | Сборка книги | Ядро запускает `adapter\build.ps1 -Target -SourceRoot` в отдельном процессе | код возврата сборки | 8.1 |
| 8.1 | книга, папка `bak\` | Бэкап | `build.ps1` копирует книгу в `bak\ReportMTO.xlsm.<время>.bak` до любых правок | файл бэкапа | 8.2 |
| 8.2 | бэкап, COM-инстанс Excel | Открытие книги | `build.ps1` создаёт свой `Excel.Application` (невидимый) и открывает книгу | `$wb` | 8.3 |
| 8.3 | 11 файлов `src\vba\*.bas` | Импорт VBA-модулей | Для каждого модуля по алфавиту (`modAggregate`, `modAIGateway`, `modColor`, `modContentDisc`, `modContentMTO`, `modContentZone`, `modHTMLEngine`, `modLog`, `modMain`, `modPivotBuilder`, `modPQSync`): удалить существующий компонент `VBComponents.Item(имя)`, перекодировать UTF-8→1251, `VBComponents.Import()` | модули в книге; маркеры `VBA_ADDED`/`VBA_DIFF` на каждый модуль | 8.4 |
| 8.4 | 16 файлов `src\powerquery\*.pq` | Обновление Power Query | Для каждого запроса: `Workbook.Queries.Item(имя).Formula = текст` или `Queries.Add(имя, формула)`; нюанс ReportMTO: `qDiagImport.pq` пропускается (точка адаптации) | запросы в книге; маркеры `PQ_ADDED`/`PQ_DIFF` | 8.5 |
| 8.5 | `tmp_index.html` | Перенос шаблона | Точка адаптации: в ReportMTO — запись содержимого шаблона в ячейку книги; в общем адаптере — комментарий для доработки | шаблон в книге | 8.6 |
| 8.6 | `$wb` | Сохранение и закрытие | `$wb.Save()`, `Close`, `Excel.Quit`; маркер `BUILD_OK` | книга собрана, код 0 | 9 (код не 0 → `RELEASE_FAIL`, конец) |
| 9 | книга | Проверка/компиляция | Ядро запускает `adapter\verify.ps1 -Target`: копия в `%TEMP%`, открытие, `$excel.Run("HasColumn","x")` — VBA компилирует весь проект перед вызовом; watchdog следит за зависшим EXCEL | `VERIFY_OK` | 10 (сбой → `VERIFY_FAIL`, `RELEASE_FAIL`, конец) |
| 10 | `release.state` (строка `release_no 9`) | Счётчик релизов | `$newReleaseNo = release_no + 1`; при первом прогоне — `$StartReleaseNo` | `$newReleaseNo = 10`, маркер `RELEASE_NO 10` | 11 |
| 11 | книга после сборки | Версия для гейтинга миграций | Повторное `stamp.ps1 -Read`: книга несёт старый штамп (`8.1.9`), по нему решается, какие миграции не применялись | `$artifactVersion = "8.1.9"` | 12 |
| 12 | `install\migrations\*.ps1` | Выбор миграций | Имена вида `<версия>__<имя>`; `8.1.0__variable_keys.ps1`: версия миграции `8.1.0` ≤ `8.1.9` → пропуск (`MIG_SKIP`); если бы была моложе — `MIG_RUN` через `context.ps1` (открыть → `-Workbook` → сохранить → закрыть) | `$applied = @()` | 13 |
| 13 | `$newVersion="8.1.10"`, `$stampDate`, `$digest`, `$newReleaseNo=10` | Запись штампа | `stamp.ps1` (режим записи) открывает книгу и пишет `CustomDocumentProperties`: `BuildVersion=8.1.10`, `BuildDate`, `BuildSrcMd5`, `BuildReleaseNo=10`; сохраняет | свойства файла обновлены, маркер `STAMP_WRITTEN 8.1.10 (10)` | 14 |
| 14 | `install\VERSION`, `$newVersion` | Сброс VERSION | Версия изменилась: первая строка → `8.1.10`, ниже — пустая инструкция «впишите описание следующей версии»; старое описание остаётся только в CHANGELOG | VERSION обновлён, маркер `VERSION_WRITTEN` | 15 |
| 15 | `$map`, `$digest`, `$newReleaseNo` | Запись состояния | `Write-State`: `version 8.1.10`, `digest …`, `release_no 10`, `file <путь> <md5>` на каждый исходник | `release.state` обновлён, `STATE_WRITTEN` | 16 |
| 16 | те же данные | Генерация манифеста | `Write-BuildInfo`: JSON `{project, adapter, release_no, version, date, digest, files[{path, md5}]}` в `install\build-info.json` | `BUILDINFO_WRITTEN` | 17 |
| 17 | `$desc`, `$changedFiles`, `$applied` | Запись CHANGELOG | Заголовок `## 8.1.10 (10) — 16.09.2026`; первым — человеческое описание из VERSION (пусто → строка-плейсхолдер); затем техника: «Изменены исходники: …», «Миграции: …», «Артефакт: …», «Хеш исходников: …» | `CHANGELOG_WRITTEN` | 18 |
| 18 | всё выше | Финал | Маркер `RELEASE_OK 8.1.10 (10) - артефакт …`, код возврата 0 | релиз завершён | конец |

Если исходники не менялись, миграций нет и нет `-Force` — шаг 17 пропускается
(`CHANGELOG_SKIP`), версия не поднимается, остальное пишется как есть
(идемпотентный прогон).

## 4. Состояние файлов после релиза

`install\VERSION`:

```
8.1.10

Первая строка этого файла - версия сборки, её ведёт install.ps1.
Ниже, до следующего релиза, впишите человеческое описание изменений:
  что добавлено; какая ошибка исправлена; что и с каким результатом оптимизировано.
Оно попадёт в CHANGELOG.md первым абзацем записи новой версии.
```

`install\release.state` (фрагмент):

```
version 8.1.10
digest 5a25c162a7d011677551626afd2e65f8
release_no 10
file src\vba\modAggregate.bas 07a3…
… (по строке на каждый исходник)
```

`install\build-info.json` (фрагмент):

```json
{
  "project": "ReportMTO",
  "adapter": "excel",
  "release_no": 10,
  "version": "8.1.10",
  "date": "2026-09-16 22:10",
  "digest": "5a25c162a7d011677551626afd2e65f8",
  "files": [ { "path": "src\\vba\\modMain.bas", "md5": "…" }, … ]
}
```

`CHANGELOG.md` (новая запись сверху):

```
## 8.1.10 (10) — 16.09.2026

Исправлена ошибка сортировки очереди загрузки: файлы теперь упорядочиваются
по дате/времени из имени, а не по имени. (человеческое описание)

- Изменены исходники: src\vba\modMain.bas, src\powerquery\Query-ImportJSON.pq
- Артефакт: C:\Projects\ReportMTO\ReportMTO.xlsm
- Хеш исходников: 5a25c162a7d011677551626afd2e65f8
```

Книга: в свойствах файла `BuildVersion=8.1.10`, `BuildReleaseNo=10`; подвал
отчёта читает их и печатает «сборка 8.1.10 (10)».

## 5. Следующий релиз 8.1.11 (11) — отличия от первого

1. В `install\VERSION` человек вписывает новое описание (после релиза там
   пустая заготовка).
2. `-DryRun` показывает `DESC_FOUND` и `RELEASE_VERSION_NEXT 8.1.11`.
3. Хеш изменился только у правленного файла — в CHANGELOG попадёт именно он.
4. Счётчик: `release_no` в `release.state` уже `10` → новое `11`.
5. Гейтинг миграций: версия книги `8.1.10` — все миграции `≤ 8.1.10`
   пропускаются.
6. Защита от отката: если на второй машине книга уже `8.1.12` — релиз
   остановится (`RELEASE_FAIL`), нужен `git pull` или осознанный `-Force`.

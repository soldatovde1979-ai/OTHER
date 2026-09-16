<!-- Версия 1.0 от 15.09.2026. Первая редакция: полный справочник по настройке агентов Roo Code (zoo-code),
     данные по встроенным режимам извлечены из установленного расширения zoo-code 3.82.1 (webview-ui/build/assets/index.js). -->

# _ROO-AGENTS — настройка агентов Roo (Zoo Code)

Подсистема-хранилище стандартов настройки агентов Roo Code (в этой среде расширение называется **zoo-code**,
поэтому ключи настроек имеют префикс `zoo-code.*`). Здесь лежат справочники, шаблоны правил, режимов,
slash-команд, skills, MCP и примеры файлов настроек. Файлы подсистемы — «доноры» для других проектов:
копируются, а не редактируются на месте в других проектах.

## Карта папок подсистемы

| Путь | Назначение |
|---|---|
| [`reafme.md`](reafme.md) | этот справочник |
| [`info.md`](info.md) | инструкции агентов разных направлений (встроенные режимы, источники на GitHub) |
| [`промпт.md`](промпт.md) | ОРИГИНАЛЫ промптов без перевода: системный промпт среды, встроенные режимы, команды folders/rules/c, кастомные инструкции |
| [`промптру.md`](промптру.md) | русский перевод промпт.md + инструкция «Как изменять этот файл» |
| [`rules/`](rules/01-общие.md) | шаблон правил для ВСЕХ режимов (копировать в `<проект>/.roo/rules/`) |
| [`rules-code/`](rules-code/01-code.md) | правила только для режима `code` (`<проект>/.roo/rules-code/`) |
| [`rules-architect/`](rules-architect/01-architect.md) | правила режима `architect` |
| [`rules-ask/`](rules-ask/01-ask.md) | правила режима `ask` |
| [`rules-debug/`](rules-debug/01-debug.md) | правила режима `debug` |
| [`rules-orchestrator/`](rules-orchestrator/01-orchestrator.md) | правила режима `orchestrator` |
| [`rules-techwriter/`](rules-techwriter/01-techwriter.md) | правила режима `techwriter` (технический писатель) |
| [`commands/`](commands/00-пример-команды.md) | шаблон slash-команд (`<проект>/.roo/commands/`) |
| [`skills/`](skills/example-skill/SKILL.md) | шаблон skills (`<проект>/.roo/skills/<имя>/SKILL.md`) |
| [`settings/`](settings/vscode-settings.example.jsonc) | примеры ГЛОБАЛЬНЫХ настроек (VS Code settings, custom_modes, MCP, ENV) |
| [`.roomodes`](.roomodes) | шаблон кастомных режимов проекта (YAML) |
| [`.rooignore`](.rooignore) | шаблон игнора файлов для ИИ |
| [`.gitignore.example`](.gitignore.example) | что коммитить/игнорить в git для `.roo/` |
| [`mcp.example.jsonc`](mcp.example.jsonc) | шаблон проектного MCP-конфига (`.roo/mcp.json`) |
| [`system-prompt-code.example.md`](system-prompt-code.example.md) | шаблон переопределения системного промпта режима (`.roo/system-prompt-code`) |

## 1. Где лежат настройки

| Область | Путь | Что там |
|---|---|---|
| Глобально (все проекты) | `C:\Users\<user>\.roo\` | `rules/`, `rules-<slug>/`, `commands/`, `skills/` |
| Глобально (настройки расширения) | `%APPDATA%\Code\User\globalStorage\zoocodeorganization.zoo-code\settings\` | `custom_modes.yaml`, `mcp_settings.json`; история задач — в соседней `tasks\` |
| Проект | `<проект>/.roo/` | те же элементы, действуют только в этом проекте |
| Корень проекта | `.roomodes` | кастомные режимы только этого проекта |
| Корень проекта | `.rooignore` | файлы/папки, которые ИИ игнорирует |
| VS Code | `.vscode/settings.json` | ключи `zoo-code.*` |

Глобальное `~/.roo/` загружается **первым**, затем проектное `.roo/`, затем режим-специфичные правила.
Файлы внутри `rules/` читаются рекурсивно; порядок — по алфавиту имён, поэтому принята нумерация
`01-...`, `02-...`.

## 2. Правила для агентов (Custom Instructions)

- Все режимы: `<проект>/.roo/rules/*.md` и глобально `~/.roo/rules/*.md`.
- Конкретный режим: `<проект>/.roo/rules-<slug>/*.md` (slug: `ask`, `architect`, `code`, `debug`,
  `orchestrator`, или slug вашего кастомного режима). Имя папки должно точно совпадать со slug.
- Устаревшие однострочные форматы (совместимость): `.roorules` (все режимы) и `.roorules-<slug>` в корне
  проекта; `.clinerules` и `.clinerules-<slug>` — совместимость с Cline.
- Тумблер `zoo-code.useAgentRules` включает/выключает использование `.roo/rules*`.
- При конфликте глобального и проектного правила побеждает **проектное** (загружается позже).

## 3. Режимы (встроенные, zoo-code 3.82.1)

| Slug | Имя | Группы прав | Назначение |
|---|---|---|---|
| `ask` | Ask | read, mcp | вопросы, объяснения, анализ без правок |
| `architect` | Architect | read, mcp, edit только `*.md` | планирование и проектирование |
| `code` | Code | read, edit, command, mcp | написание и правка кода |
| `debug` | Debug | read, edit, command, mcp | систематическая отладка |
| `orchestrator` | Orchestrator | (нет прямых прав — делегирует через `new_task`) | координация подзадач между режимами |

Полные тексты `roleDefinition`, `whenToUse`, `customInstructions` каждого режима — в
[`info.md`](info.md).

### Кастомные режимы

- Проект: `.roomodes` в корне проекта (YAML).
- Глобально: `settings/custom_modes.yaml` в `globalStorage\zoocodeorganization.zoo-code\settings\`.
- Поля: `slug` (уникальный), `name`, `description`, `roleDefinition`, `whenToUse`, `customInstructions`,
  `groups` (список `read`, `edit`, `browser`, `command`, `mcp`), опционально `fileRegex` для ограничения
  типа файлов. Пример — [`settings/custom_modes.example.yaml`](settings/custom_modes.example.yaml) и
  [`.roomodes`](.roomodes).

## 4. Slash-команды

- Файлы `.md` в `<проект>/.roo/commands/` (или глобально `~/.roo/commands/`).
- Имя команды = имя файла без расширения. Описание — в YAML-frontmatter ключом `description`.
- Пример — [`commands/00-пример-команды.md`](commands/00-пример-команды.md).

## 5. Skills

- Папка `<проект>/.roo/skills/<имя-скилла>/SKILL.md` (или `~/.roo/skills/...`).
- Frontmatter: `name`, `description`. Тело — инструкция для агента.
- Пример — [`skills/example-skill/SKILL.md`](skills/example-skill/SKILL.md).
- Доступность зависит от версии расширения — проверить в UI (Settings → Skills).

## 6. MCP-серверы

- Проект: `.roo/mcp.json`. Глобально: `settings/mcp_settings.json` (правка — через UI, поле «MCP»).
- Сервер stdio: `command`, `args`, `env`, `cwd`. Удалённые: `type: "sse"` или `type: "streamable-http"`
  с `url` и `headers`. Общие поля: `disabled`, `alwaysAllow`, `timeout`.
- Секреты (токены) — только через ENV-переменные, не в файле конфига.
- Примеры — [`mcp.example.jsonc`](mcp.example.jsonc) и [`settings/mcp_settings.example.jsonc`](settings/mcp_settings.example.jsonc).

## 7. Игноры

- `.rooignore` в корне проекта: ИИ не читает/не ищет/не правит совпавшие файлы. Синтаксис как у
  `.gitignore` (плюс `!`-негация). Работает независимо от `.gitignore`.
- В `.gitignore` для `.roo/` принято коммитить: `rules*/`, `commands/`, `mcp.json`, `skills/`.
  Не коммитят: локальные переопределения, кэш. Пример — [`.gitignore.example`](.gitignore.example).
- Настройка UI `rooignore` — показывать ли игнорируемые файлы в списках (со значком замка).

## 8. Ключи настроек VS Code (`zoo-code.*`)

Подтверждённые ключи из `package.json` zoo-code 3.82.1:

- `zoo-code.allowedCommands`, `zoo-code.deniedCommands` — списки разрешённых/запрещённых команд.
- `zoo-code.commandExecutionTimeout`, `zoo-code.commandTimeoutAllowlist` — таймауты команд.
- `zoo-code.apiRequestTimeout` — таймаут API.
- `zoo-code.useAgentRules` — включать правила `.roo/rules*`.
- `zoo-code.newTaskRequireTodos`, `zoo-code.preventCompletionWithOpenTodos` — todo-дисциплина.
- `zoo-code.enableCodeActions` — действия из контекстного меню.
- `zoo-code.debug`, `zoo-code.debugProxy.*` — отладка расширения/прокси.
- `zoo-code.autoImportSettingsPath`, `zoo-code.customStoragePath`, `zoo-code.workspace.rootResolution` — пути.
- `zoo-code.terminalAddToContext`, `zoo-code.terminalExplainCommand`, `zoo-code.terminalFixCommand` — терминал.
- `zoo-code.maximumIndexedFilesForFileSearch`, `zoo-code.showRipgrepDiagnostic` — поиск по файлам.

Часть настроек живёт только в UI и хранится в globalStorage (auto-approve, язык, размер контекста вкладок,
autoCondenseContext и т.п.) — проверять актуальные имена в UI (Settings → Zoo Code). Шаблон рабочих
значений — [`settings/vscode-settings.example.jsonc`](settings/vscode-settings.example.jsonc).

## 9. Приоритеты и конфликты

1. Системный промпт режима (можно переопределить файлом `.roo/system-prompt-<slug>`).
2. Кастомные инструкции: глобальные → проектные → режим-специфичные (позже загруженные сильнее).
3. Прямая инструкция пользователя в сообщении сильнее любых правил из файлов.

## 10. Чек-лист внедрения в новый проект

1. Скопировать `rules/` → `<проект>/.roo/rules/`, при необходимости `rules-<slug>/`.
2. При наличии кастомных режимов — `.roomodes` в корень проекта.
3. Создать `.rooignore` (исключить `data/`, `result/`, секреты, большие бинарники).
4. При необходимости MCP — `.roo/mcp.json`; секреты — ENV.
5. Проверить `.vscode/settings.json` (ключи `zoo-code.*`).
6. Добавить `.roo/rules*`, `.roo/commands/`, `.roo/mcp.json` в git (по политике проекта).

## Правила для агента: доступ к папкам

- Читать можно: все `.md`/`.jsonc`/`.yaml` этой подсистемы.
- Не редактировать оригиналы шаблонов при переносе в другой проект — только копировать.
- Без явного запроса не ходить в: `%APPDATA%\Code\User\globalStorage\zoocodeorganization.zoo-code\tasks\`
  (история задач), `state.vscdb` (настройки UI) — только конкретный файл по имени.
- Не удалять и не перемещать файлы подсистемы без согласования.

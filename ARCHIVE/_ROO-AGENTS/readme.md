# _ROO-AGENTS — подсистема настройки агентов Roo (Zoo Code)

## Как формируется общий промпт для роли

1. **База** — системный промпт режима: `roleDefinition`, `whenToUse`, `customInstructions`
   встроенного режима (полные тексты — в [`00-system-readonly.md`](USERPROFILE/.roo/rules/00-system-readonly.md),
   перевод — [`00-системное-ТолькоЧтение.md`](USERPROFILE/.roo/rules/00-системное-ТолькоЧтение.md)) или кастомного
   (`.roomodes` в корне проекта / `custom_modes.yaml` глобально, эталон — [`custom_modes.yaml`](USERPROFILE/.roo/settings-global/custom_modes.yaml)).
   Может переопределяться файлом `.roo/system-prompt-<slug>` (заглушка — [`system-prompt-code`](PARENT/PROJECTS/.roo/system-prompt-code)).
2. **Поверх базы** — кастомные инструкции в порядке загрузки: глобальные `~/.roo/rules/*.md` →
   проектные `<проект>/.roo/rules/*.md` → режим-специфичные `rules-<slug>/*.md`.
   Файлы читаются рекурсивно, порядок — по алфавиту имён (нумерация `01-`, `02-`).
   Позже загруженные сильнее: проектные правила побеждают глобальные.
3. **Верхний приоритет** — прямая инструкция пользователя в сообщении сильнее любых правил из файлов.

## Параллельные агенты

Задачи агентов привязаны к окну VS Code: каждая задача живёт в своём окне/вкладке и своём
extension host. Новая задача в другом окне не останавливает старые — они останавливаются,
если окно **закрыто** или задача встала на паузу в ожидании подтверждения.

Способы запустить несколько агентов одновременно:

- **В разных окнах** (надёжный способ, работает во всех версиях zoo-code): `File → New Window`
  на каждый проект/задачу; старые окна **сворачивать, но не закрывать** — агенты в неактивном
  окне продолжают работу в фоне.
- **В одном окне — вкладки задач**: если в панели задач расширения есть «+» (New Task),
  каждый новый таб запускает независимого агента, и они работают параллельно. В версиях без
  этой кнопки используйте отдельные окна.
- Задачи с ручным подтверждением в неактивном окне встают на паузу и «выглядят остановленными»:
  для автономной работы включите авто-апрув или возвращайтесь в окно для подтверждения.

## Зачем нужна

Хранилище стандартов настройки агентов Roo Code (в этой среде расширение называется **zoo-code**).
Здесь лежат справочники (оригиналы промптов встроенных режимов) и слои-слепки реальных
настроек zoo: [`USERPROFILE/`](USERPROFILE) (профиль) и [`PARENT/PROJECTS/`](PARENT/PROJECTS) (проект).

## Описание файлов

| Файл / папка | Назначение |
|---|---|
| [`USERPROFILE/.roo/rules/`](USERPROFILE/.roo/rules) | общие правила профиля: [`00-system-readonly.md`](USERPROFILE/.roo/rules/00-system-readonly.md) (оригинал системного промпта), [`00-системное-ТолькоЧтение.md`](USERPROFILE/.roo/rules/00-системное-ТолькоЧтение.md) (перевод), [`01-общие.md`](USERPROFILE/.roo/rules/01-общие.md), [`02-rac-predlojenia.md`](USERPROFILE/.roo/rules/02-rac-predlojenia.md), [`02-signature-rule.md`](USERPROFILE/.roo/rules/02-signature-rule.md), [`02-signature-slash_c.md`](USERPROFILE/.roo/rules/02-signature-slash_c.md), [`03-engAI.md`](USERPROFILE/.roo/rules/03-engAI.md) |
| [`USERPROFILE/.roo/rules-<slug>/`](USERPROFILE/.roo/rules-architect) | режим-специфичные правила профиля: `architect`, `ask`, `code`, `debug`, `orchestrator`, `techwriter` (у `architect`, `ask`, `code` есть ReadOnly-справочники `00-*`) |
| [`USERPROFILE/.roo/commands/`](USERPROFILE/.roo/commands) | команды профиля: [`c.md`](USERPROFILE/.roo/commands/c.md) — git-синхронизация (`/c`), [`folders.md`](USERPROFILE/.roo/commands/folders.md) — стандарт структуры папок, [`rules.md`](USERPROFILE/.roo/commands/rules.md) — консолидация `rules.md` проектов |
| [`USERPROFILE/.roo/settings-global/`](USERPROFILE/.roo/settings-global) | эталоны глобальных настроек: [`custom_modes.yaml`](USERPROFILE/.roo/settings-global/custom_modes.yaml) (кастомные режимы), [`mcp_settings.json`](USERPROFILE/.roo/settings-global/mcp_settings.json) (MCP-серверы) |
| [`USERPROFILE/.roo/skills/example-skill/SKILL.md`](USERPROFILE/.roo/skills/example-skill/SKILL.md) | пример скилла профиля |
| [`USERPROFILE/.roo/.gitignore`](USERPROFILE/.roo/.gitignore) | исключения профиля |
| [`USERPROFILE/.agents/skills/SKILL.md`](USERPROFILE/.agents/skills/SKILL.md) | заглушка второго источника скиллов |
| [`PARENT/PROJECTS/AGENTS.md`](PARENT/PROJECTS/AGENTS.md) | заглушка проектных инструкций |
| [`PARENT/PROJECTS/.roomodes`](PARENT/PROJECTS/.roomodes) | заглушка кастомных режимов проекта |
| [`PARENT/PROJECTS/.rooignore`](PARENT/PROJECTS/.rooignore) | заглушка исключений Roo |
| [`PARENT/PROJECTS/.vscode/settings.json`](PARENT/PROJECTS/.vscode/settings.json) | настройки VS Code проекта |
| [`PARENT/PROJECTS/.roo/rules/`](PARENT/PROJECTS/.roo/rules) | проектные правила: [`00-system.md`](PARENT/PROJECTS/.roo/rules/00-system.md), [`01-общие.md`](PARENT/PROJECTS/.roo/rules/01-общие.md) |
| [`PARENT/PROJECTS/.roo/rules-<slug>/`](PARENT/PROJECTS/.roo/rules-architect) | режим-специфичные правила проекта: `architect`, `ask`, `code`, `debug`, `orchestrator`, `techwriter` |
| [`PARENT/PROJECTS/.roo/commands/`](PARENT/PROJECTS/.roo/commands) | команды проекта: [`00-пример-команды.md`](PARENT/PROJECTS/.roo/commands/00-пример-команды.md) (заглушка) |
| [`PARENT/PROJECTS/.roo/skills/example-skill/SKILL.md`](PARENT/PROJECTS/.roo/skills/example-skill/SKILL.md) | пример скилла проекта |
| [`PARENT/PROJECTS/.roo/mcp.json`](PARENT/PROJECTS/.roo/mcp.json) | заглушка MCP-конфигурации проекта |
| [`PARENT/PROJECTS/.roo/system-prompt-code`](PARENT/PROJECTS/.roo/system-prompt-code) | заглушка переопределения системного промпта режима `code` |
| [`PARENT/PROJECTS/.agents/skills/SKILL.md`](PARENT/PROJECTS/.agents/skills/SKILL.md) | заглушка второго источника скиллов |

Слои-слепки реальных настроек zoo:
[`USERPROFILE/`](USERPROFILE) — профиль (`~/.roo`), [`PARENT/PROJECTS/`](PARENT/PROJECTS) — проект.
Пустые файлы помечены «заглушка».

## Каталог `.agents`

Второй (параллельный `.roo`) источник **skills** (проверено в коде zoo-code 3.82.2, функция
`getSkillsDirectories()`). Расширение ищет скиллы в 8 местах:

- `~/.roo/skills/`, `~/.roo/skills-<mode>/`
- `~/.agents/skills/`, `~/.agents/skills-<mode>/`
- `<проект>/.roo/skills/`, `<проект>/.roo/skills-<mode>/`
- `<проект>/.agents/skills/`, `<проект>/.agents/skills-<mode>/`

Формат скилла: подпапка `<имя>/SKILL.md` с frontmatter `name` (совпадает с именем папки) и `description`.

В слепках обоих слоёв лежат пустые заглушки: [`USERPROFILE/.agents/skills/SKILL.md`](USERPROFILE/.agents/skills/SKILL.md)
и [`PARENT/PROJECTS/.agents/skills/SKILL.md`](PARENT/PROJECTS/.agents/skills/SKILL.md).

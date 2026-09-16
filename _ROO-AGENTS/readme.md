# _ROO-AGENTS — подсистема настройки агентов Roo (Zoo Code)

## Как формируется общий промпт для роли

1. **База** — системный промпт режима: `roleDefinition`, `whenToUse`, `customInstructions`
   встроенного режима (полные тексты — в [`info.md`](info.md)) или кастомного
   ([`.roomodes`](.roomodes) / [`settings/custom_modes.example.yaml`](settings/custom_modes.example.yaml)).
   Может переопределяться файлом `.roo/system-prompt-<slug>`
   (шаблон — [`system-prompt-code.example.md`](system-prompt-code.example.md)).
2. **Поверх базы** — кастомные инструкции в порядке загрузки: глобальные `~/.roo/rules/*.md` →
   проектные `<проект>/.roo/rules/*.md` → режим-специфичные `rules-<slug>/*.md`.
   Файлы читаются рекурсивно, порядок — по алфавиту имён (нумерация `01-`, `02-`).
   Позже загруженные сильнее: проектные правила побеждают глобальные.
3. **Верхний приоритет** — прямая инструкция пользователя в сообщении сильнее любых правил из файлов.

Полное описание механики — в [`reafme.md`](reafme.md).

## Зачем нужна

Хранилище стандартов настройки агентов Roo Code (в этой среде расширение называется **zoo-code**).
Здесь лежат справочники и шаблоны: правила режимов, slash-команды, skills, MCP, примеры файлов настроек.
Файлы подсистемы — «доноры» для других проектов: они копируются в проект, а не редактируются на месте.

## Описание файлов

| Файл / папка | Назначение |
|---|---|
| [`reafme.md`](reafme.md) | полный справочник по подсистеме: карта папок, где лежат настройки, правила, режимы, slash-команды, skills, MCP |
| [`info.md`](info.md) | инструкции агентов разных направлений (встроенные режимы, источники на GitHub) |
| [`промпт.md`](промпт.md) | оригиналы промптов без перевода (системный промпт, встроенные режимы, команды) |
| [`промптру.md`](промптру.md) | русский перевод [`промпт.md`](промпт.md) + инструкция по изменению файла |
| [`rules/`](rules/00-system.md) | шаблон правил для всех режимов |
| [`rules-code/`](rules-code/01-code.md) | правила режима `code` |
| [`rules-architect/`](rules-architect/01-architect.md) | правила режима `architect` |
| [`rules-ask/`](rules-ask/01-ask.md) | правила режима `ask` |
| [`rules-debug/`](rules-debug/01-debug.md) | правила режима `debug` |
| [`rules-orchestrator/`](rules-orchestrator/01-orchestrator.md) | правила режима `orchestrator` |
| [`rules-techwriter/`](rules-techwriter/01-techwriter.md) | правила режима `techwriter` |
| [`commands/`](commands/00-пример-команды.md) | шаблон slash-команд |
| [`skills/`](skills/example-skill/SKILL.md) | шаблон skills |
| [`settings/`](settings/vscode-settings.example.jsonc) | примеры глобальных настроек (VS Code, custom_modes, MCP, ENV) |
| [`.roomodes`](.roomodes) | шаблон кастомных режимов проекта (YAML) |
| [`.rooignore`](.rooignore) | шаблон игнора файлов для ИИ |
| [`.gitignore.example`](.gitignore.example) | что коммитить/игнорить в git для `.roo/` |
| [`mcp.example.jsonc`](mcp.example.jsonc) | шаблон проектного MCP-конфига |
| [`system-prompt-code.example.md`](system-prompt-code.example.md) | шаблон переопределения системного промпта режима |

Полное описание — в [`reafme.md`](reafme.md).

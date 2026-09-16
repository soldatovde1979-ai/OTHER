# !OTHER

Пул стандартных подсистем, переиспользуемых другими проектами, и материалы помощи другим проектам (пробы, прокси, служебные скрипты).

## Карта папок

- `docs/` — документация: [`docs/rules.md`](docs/rules.md) — правила проекта (сеть, инструменты), [`docs/ConnectToGeminiAPI.md`](docs/ConnectToGeminiAPI.md).
- `doc/spec/` — правила и спецификации: [`doc/spec/subsystems-readme.md`](doc/spec/subsystems-readme.md) — правило: каждая подсистема (папка с префиксом `_`) обязана иметь свой `readme.md`.
- `tools/` — скрипты и утилиты.
- `_ROO-AGENTS/` — стандарт настройки агентов Roo (zoo-code): справочники, шаблоны правил режимов, slash-команд, skills, MCP и файлов настроек — вход [`_ROO-AGENTS/readme.md`](_ROO-AGENTS/readme.md), полный справочник [`_ROO-AGENTS/reafme.md`](_ROO-AGENTS/reafme.md).
- `_VERSION/` — инструкции и скрипты версионирования сборки — вход [`_VERSION/readme.md`](_VERSION/readme.md), инструкция пользователя [`_VERSION/doc-version.md`](_VERSION/doc-version.md).
- Корневые служебные скрипты (пробы, прокси): `gemini_probe.py`, `gemini_probe.bat`, `xbox_proxy_server.py`, `xbox_proxy_server.ps1`, `vscode_proxy.bat`, `SertOff.bat`.

## Правила работы

- Файлы отсюда используются другими проектами как «доноры»: правки — только по явному указанию.
- При переносе в другой проект — копирование, а не перемещение, если иное не согласовано.
- Документы и правила проектов в `c:/Projects/*` этим каталогом не подменяются.

## Документация

- [`docs/rules.md`](docs/rules.md)
- [`_VERSION/doc-version.md`](_VERSION/doc-version.md)

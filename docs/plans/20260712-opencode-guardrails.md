# opencode-guardrails — распространяемая система уровней подтверждений

> Пересмотрено после grill-сессии (см. `CONTEXT.md`, `docs/adr/0001-*`). Ключевые
> изменения против первой редакции: (1) модель угроз — только «неосторожный агент»;
> (2) overlay — основной путь установки через `OPENCODE_CONFIG`-layering; (3)
> двухуровневый floor (секреты `deny`, прочие скрытые `ask`); (4) генератор и
> `src/`→`dist/`-CI убраны — три агента и overlay пишутся руками.

## Overview

Дать opencode **систему уровней строгости подтверждений**: от самого строгого
(каждое действие спрашивает) до самого «смелого» (почти всё разрешено). Уровни —
три primary-агента, циклятся Tab.

**Модель угроз — только «неосторожный агент» (model A).** floor снижает
*случайные* чтения секретов и деструктивные команды. Это **НЕ** граница безопасности
против враждебной prompt-injection (config-паттерны ею быть не могут). Полное
обоснование — `docs/adr/0001-threat-model-careless-agent.md`. Кто хочет защиту от
атакующего — получает её композицией с OS-sandbox (раздел README «Hardening»).

**Что продукт делает:**

- **Добавляет** три primary-агента `guard-strict` / `guard-normal` / `guard-loose`.
- **Заменяет** пару `build`/`plan` (гасит их и ставит `guard-normal` дефолтом) —
  через тонкий **overlay** (`default_agent` + `disable`), который применяется
  **config-layering'ом** (`OPENCODE_CONFIG`), НЕ правкой чужого `opencode.json`.
  Это основной путь установки (см. Technical Details). **Оговорка (правка codex
  CRITICAL 3):** overlay идёт в слой `custom`, а он по precedence НИЖЕ `project`
  (`remote → global → custom → project`). Значит существующий **project-конфиг
  пользователя может переопределить** наш `default_agent`/`disable`. Гарантия замены —
  «при отсутствии конфликтующего project-конфига»; точную формулировку и, при
  необходимости, механизм с нужным приоритетом фиксируем по Task 1.

**floor — двухуровневый, дописан последним (last-match-wins, подтверждено доками):**

- **Жёсткие секреты → `deny`** (на `read`), **ПАРНЫЕ root+nested** (т.к. `*` не
  пересекает `/`) и **anchored, а не substring** (правка plan-review CRITICAL — широкие
  `*credential*`/`secrets*` дают ложный deny на доках вроде `credentials-guide.md`, что
  вредит модели A): `.env`/`.env*`/`**/.env*`, `*.pem`/`**/*.pem`, `*.key`/`**/*.key`,
  `id_rsa*`/`**/id_rsa*`, `credentials`/`credentials.*`/`**/credentials`/`**/credentials.*`,
  `secrets`/`secrets.*`/`**/secrets`/`**/secrets.*`. `deny` переживает `--auto`
  (auto-approve гасит `ask`, но не `deny`) и расширяет встроенный `.env`-deny opencode.
  Финальный список — под точную семантику матчера из Task 1.
- **Прочие скрытые файлы → `ask`** (на `read`): `.*`, `**/.*` — это **dot-именованные**
  файлы (`.gitignore`, `.eslintrc`; часто нужны легитимно). **Scope-оговорка:** `*` не
  пересекает `/`, поэтому НЕ-dot-именованные файлы **внутри** скрытых директорий
  (`.git/config`, `.aws/config`) этим слоем НЕ покрыты и следуют уровню; но **секреты**
  внутри скрытых папок (`.aws/credentials`, `.ssh/id_rsa`) ловятся anchored deny-паттернами
  (`**/credentials`, `**/id_rsa*`). Этот слой условен: `--auto`/`always` могут подавить prompt.
- **Опасный bash → `ask` (best-effort)**: прямые формы `rm`, `git push`,
  `git reset --hard`, `chmod`, `curl … | sh` и т.п. + best-effort секрет-чтение
  (`cat .env`). Обходится цепочками/обфускацией — это и есть граница модели A.

Ключевые выгоды:
- один понятный переключатель строгости вместо `build`/`plan`;
- сильная защита *чтения* секретов (`deny`, переживает `--auto`) + honest best-effort
  по bash — с явно очерченной границей (модель A);
- ноль зависимостей у пользователя; артефакт — чистые данные, которые ставятся как есть.

## Context (from discovery)

**Подтверждено официальными доками opencode** (сняло половину прежних рисков Task 1):

- last-match-wins: *«the last matching rule winning… put the catch-all `"*"` first,
  and more specific rules after»* — ровно механизм floor. ✓
- permission на инструмент = **объект glob-паттернов** (`"bash": {"*":"ask","git *":"allow"}`). ✓
- **`default_agent`** — top-level настройка (`"default_agent": "plan"`; неверное → фолбэк
  на `build` с ворнингом). ✓
- **`disable: true`** для агентов (можно гасить встроенные `build`/`plan`). ✓
- **`OPENCODE_CONFIG`** + *«configuration files are merged together, not replaced»*
  (порядок `remote → global → custom → project`); есть `OPENCODE_CONFIG_DIR`,
  `OPENCODE_CONFIG_CONTENT`. → overlay ставится отдельным файлом, чужой конфиг не трогаем. ✓
- **`.env` — `deny` по умолчанию** (`*.env`, `*.env.*`, кроме `*.env.example`). ✓
- **`--auto`** гасит только `ask`, `deny` остаётся; session `always` — whitelist на сессию. ✓
- **bash матчится по РАСПАРСЕННОЙ команде** (не по строке). ✓
- permission во frontmatter `.md` (`permission: { edit: deny, bash: deny }`). ✓
- **`config set`-команды НЕТ**; launch-флаг `--agent` эфемерный. ✓
- Агенты: `~/.config/opencode/agents/*.md` (global) / `.opencode/agents/*.md` (project).

Источники: [Config](https://opencode.ai/docs/config/), [Agents](https://opencode.ai/docs/agents/),
[CLI](https://opencode.ai/docs/cli/), [Permissions](https://opencode.ai/docs/permissions/).

**Осталось подтвердить на живом opencode (Task 1)** — немного:
- точный синтаксис `disable` для встроенных `build`/`plan` и что они уходят из Tab-цикла;
- `OPENCODE_CONFIG` **добавляет** слой или **подменяет** дискаверинг global (docs → «merge»,
  но проверить); либо предпочесть `OPENCODE_CONFIG_DIR` как drop-in;
- уважают ли `grep`/`glob` встроенный `.env`-deny (если да — `allow` на `normal` безопасен);
- форма пути, которую `read` передаёт permission engine (относит. к worktree?);
- формат frontmatter (YAML/JSON/TOML) — от него зависит, как пишем `.md`;
- точные распарсенные формы bash-команд для `dangerous_bash`.

Окружение:
- Корень репо = `/home/mgcom/mkozhin/opencode-guardrails` (пути в задачах — ОТ КОРНЯ).
- Уже созданы: `AGENTS.md`, `CLAUDE.md` (`@AGENTS.md`), `CONTEXT.md`, `docs/adr/0001-*`.
- **opencode НЕ установлен здесь** → Task 1 выполняется на машине с opencode. Hard gate.

## Development Approach

- **Артефакт пишется руками, без генератора.** Три `agents/guard-*.md` + `opencode.json`
  overlay — это и есть deliverable, коммитятся и ставятся напрямую. Нет `src/`→`dist/`,
  нет `build.py`, нет CI-записи в `main`. Обоснование: три редко меняющихся файла ниже
  порога, где codegen-пайплайн окупается.
- **Дрейф floor между тремя файлами ловит инвариант-тест** (floor побайтово одинаков и
  стоит последним в `read`/`bash` всех трёх). Это замена главной ценности генератора.
- **Testing**: Python stdlib (`unittest`), ноль зависимостей. Тесты — отдельные чекбоксы,
  success + error, прогон `python -m unittest discover tests` перед следующей задачей.
- маленькие сфокусированные изменения; план держим в синхроне со scope.

## Testing Strategy

- **`tests/test_agents.py`** (stdlib `unittest`) — главный тест артефакта. Резолвинг
  last-match-wins — **документированный helper `resolve()` внутри этого файла** (модель
  семантики opencode, НЕ авторитетная реализация; правка codex по over-engineering —
  отдельный модуль убран, seam гипотетический: потребитель один):
  - **инвариант порядка**: top-level `"*"` — ПЕРВЫЙ в `permission`; внутри `read`/`bash`
    первым идёт `"*"` уровня; floor-блок (ask-hidden → deny-секреты root+nested → carve-out)
    побайтово одинаков во всех трёх `guard-*.md`;
  - **матрица реальных путей через `resolve()`** (root + nested + absolute + negative;
    согласована с anchored-паттернами):
    `deny`: `.env`, `.env.local`, `nested/.env`, `nested/.env.local`, `secret.pem`,
    `nested/app.pem`, `private.key`, `nested/app.key`, `id_rsa`, `nested/id_rsa`,
    `credentials`, `credentials.json`, `.aws/credentials`, `secrets.yaml`, `nested/secrets.yaml`;
    `ask` (dot-**именованные** файлы): `.gitignore`, `.eslintrc`, `nested/.gitignore`, `nested/.npmrc`;
    `allow` (carve-out): `.env.example`, `nested/.env.example`;
    `allow` (обычный + **negative, НЕ должны попасть в deny**): `src/main.py`,
    `credentials-guide.md`, `credential-management.md`, `secrets-overview.md`, `keynote.md`;
    (абсолютные варианты — по итогам Task 1 о форме пути);
  - **юнит-тесты самого `resolve()`**: порядок правил, carve-out перебивает deny, `*`
    не пересекает `/`;
  - **валидность**: frontmatter каждого `.md` парсится (способ — по Task 1: предпочесть
    формат со stdlib-парсером, `tomllib` для TOML / `json` для JSON; иначе минимальный
    parser известного фиксированного frontmatter — см. Task 3/4), обязательные ключи
    (`description`, `mode: primary`, `permission`) на месте; `opencode.json` overlay —
    валидный JSON с `default_agent` + `disable`;
  - error-кейсы (через `assertRaises`/отрицательный результат, тест НЕ падает сам):
    validator отклоняет битый frontmatter/JSON; инвариант ловит floor-дрейф в фикстуре.
- **`tests/test_install.sh`** — success/error `install.sh` во временных `HOME`/project
  (см. Task 5).
- **`tests/test_readme_links.py`** — локальные ссылки/пути в обоих README существуют
  (stdlib, без сетевых линтеров).
- **CI-гейт (правка codex CRITICAL 4):** `verify.yml` гоняет И `python -m unittest discover
  tests`, И **`bash tests/test_install.sh`** — `unittest discover` shell-тесты НЕ исполняет.
- **spike (Task 1)** — не юнит-тест: рантайм-проверки на реальном opencode, результаты в план.
- **Обязательный runtime smoke-gate (правка codex CRITICAL 5):** Python-`resolve()` — лишь
  модель; она зелёная, даже если рантайм opencode иной. Поэтому финальные `guard-*.md`/overlay
  ОБЯЗАТЕЛЬНО проверяются на живом opencode как **acceptance-gate в Task 8** (не post-completion):
  read обычного файла, `.env` deny, hidden ask, carve-out, dangerous bash, default_agent,
  Tab-цикл — хотя бы на одной подтверждённой версии.
- e2e UI-тестов нет — не применимо.

## Solution Overview

Три уровня как primary-агенты (циклятся Tab):

| Уровень | catch-all `"*"` | read | grep/glob | edit | bash | webfetch/websearch | task/external_directory/doom_loop |
|---------|-----------------|------|-----------|------|------|--------------------|-----------------------------------|
| **strict** | ask | ask | ask | ask | ask | ask | ask |
| **normal** (дефолт) | ask | allow† | allow‡ | ask | ask | allow | ask |
| **loose** | allow | allow† | allow‡ | allow | allow | allow | ask (external_directory/doom_loop) |

† `read` = `allow`, НО floor перебивает: жёсткие секреты → `deny`, прочие скрытые → `ask`.
‡ `grep`/`glob` = скаляр уровня (permission матчит поисковый аргумент, не пути — floor туда
бессмысленен). Уважают ли они встроенный `.env`-deny — Task 1; если нет → best-effort-дыра
на `normal`/`loose`, документируется.

**catch-all `"*"`** задаём явно в каждом уровне (не опираться на дефолты для
`task`/`external_directory`/`doom_loop`/будущих). `external_directory`/`doom_loop` = `ask`
даже на `loose`.

### Порядок правил (важно для last-match-wins)

**Top-level `"*"` — ПЕРВЫМ** в `permission` (правка codex CRITICAL 1), иначе он затирает
блоки `read`/`bash` и `ask` для `external_directory`/`doom_loop`. Внутри блока `read`
первым идёт `"*"` уровня, затем floor (побеждает последнее совпадение):

1. ask-hidden: `.*`, `**/.*` → `ask`;
2. **затем** deny-секреты, **ПАРНЫЕ root+nested** и **anchored** (не substring — правка
   plan-review CRITICAL против ложных deny на `credentials-guide.md` и т.п.):
   `.env`/`.env*`/`**/.env*`, `*.pem`/`**/*.pem`, `*.key`/`**/*.key`, `id_rsa*`/`**/id_rsa*`,
   `credentials`/`credentials.*`/`**/credentials`/`**/credentials.*`,
   `secrets`/`secrets.*`/`**/secrets`/`**/secrets.*` → `deny`;
3. **в самом конце** carve-out: `*.env.example`, `**/*.env.example` → `allow` (шаблоны).

Блок `bash`: `"*"` уровня первым, затем `dangerous_bash` (ask) — точные распарсенные формы из Task 1.

Точная форма пути (относит. к worktree? абсолютные?) подтверждается в Task 1 и может
потребовать доп-паттернов; финальный список фиксируется после Task 1.

### Известные ограничения (README, честно)

- **grep/glob**: на `normal`/`loose` могут вынести содержимое секрета (permission не
  фильтрует по путям). Строгая гарантия — только `read`. (Task 1 может закрыть, если grep
  уважает `.env`-deny.)
- **bash-обходы**: цепочки/обфускация (`echo x && rm y`, `c=cat; $c .env`) обходят
  best-effort-паттерны. Это граница модели A, не B.
- **`--auto`/`always`**: гасят `ask`-слой (но не `deny`-секреты). Гарантия формулируется
  условно для ask-слоя.

## Technical Details

Структура репозитория (пути ОТ КОРНЯ):

```
.
├── agents/
│   ├── guard-strict.md      # руками; frontmatter: description, mode: primary, permission (+floor)
│   ├── guard-normal.md
│   └── guard-loose.md
├── opencode.json            # руками; overlay: default_agent + disable build/plan
├── install.sh               # копирует agents/*.md + подключает overlay через OPENCODE_CONFIG
├── tests/
│   ├── __init__.py
│   ├── test_agents.py       # инвариант floor + матрица путей через resolve()-helper + валидность
│   ├── test_install.sh      # success/error во временных HOME/project
│   └── test_readme_links.py # локальные ссылки/пути в обоих README
├── .github/workflows/
│   └── verify.yml           # pull_request: unittest + bash test_install.sh + shellcheck (без записи в main)
├── README.md                # English (primary)
├── README_RU.md             # Russian
├── AGENTS.md / CLAUDE.md / CONTEXT.md   # уже созданы
├── docs/
│   ├── adr/0001-threat-model-careless-agent.md   # уже создан
│   └── plans/20260712-opencode-guardrails.md     # этот план
├── LICENSE                  # MIT
└── .gitignore
```

Формат `agents/<level>.md` (пример; точный формат frontmatter — Task 1):

```markdown
---
description: <level description>
mode: primary
permission:
  "*": "<lvl>"                  # top-level tool catch-all — ПЕРВЫМ (правка codex CRITICAL 1),
                               #   чтобы конкретные инструменты его переопределяли, не наоборот
  read:
    "*": "<lvl>"               # path-catch-all read — первым внутри блока
    ".*": "ask"                # 1) ask-hidden (root + nested)
    "**/.*": "ask"
    ".env": "deny"             # 2) deny-секреты: ПАРНЫЕ root + nested (правка codex CRITICAL 2)
    ".env*": "deny"
    "**/.env*": "deny"
    "*.pem": "deny"
    "**/*.pem": "deny"
    "*.key": "deny"
    "**/*.key": "deny"
    "id_rsa*": "deny"
    "**/id_rsa*": "deny"
    "credentials": "deny"      # anchored, НЕ *credential* (иначе ложный deny на credentials-guide.md)
    "credentials.*": "deny"
    "**/credentials": "deny"
    "**/credentials.*": "deny"
    "secrets": "deny"
    "secrets.*": "deny"
    "**/secrets": "deny"
    "**/secrets.*": "deny"
    "*.env.example": "allow"   # 3) carve-out шаблонов — В САМОМ КОНЦЕ (перебивает deny)
    "**/*.env.example": "allow"
  grep: "<lvl>"
  glob: "<lvl>"
  edit: "<lvl>"
  bash:
    "*": "<lvl>"
    # dangerous_bash — точные распарсенные формы из Task 1 (rm/git push/… → ask)
  webfetch: "<lvl>"
  websearch: "<lvl>"
  task: "<lvl>"
  external_directory: "ask"
  doom_loop: "ask"
---

<короткая инструкция: задаёт только уровень подтверждений, поведение модели не меняет>
```

> **Порядок ключей (инвариант, проверяется тестом):** top-level `"*"` — ПЕРВЫЙ в
> `permission`; внутри `read` первым идёт `"*"`, затем ask-hidden → deny-секреты
> (root+nested) → carve-out. `*` в glob НЕ пересекает `/` (подтверждено доками:
> `/` значим буквально), поэтому root (`*.pem`) и nested (`**/*.pem`) — обязательно ПАРНЫЕ.

Формат `opencode.json` (overlay):

```json
{
  "$schema": "https://opencode.ai/config.json",
  "default_agent": "guard-normal",
  "agent": {
    "build": { "disable": true },
    "plan":  { "disable": true }
  }
}
```

Установка overlay (основной путь) — **config layering, чужой конфиг не трогаем:**
- `install.sh` копирует `agents/*.md` в `~/.config/opencode/agents/` (или
  `./.opencode/agents/` при `--project`) и кладёт overlay-файл в известное место;
- **overlay активируется переменной `OPENCODE_CONFIG` (или `OPENCODE_CONFIG_DIR` drop-in).
  Скрипт НЕ может сам выставить env var в родительском shell** (правка codex MAJOR 3) —
  поэтому он **печатает точную команду** активации (`export OPENCODE_CONFIG=…` и как
  добавить её в shell-профиль), но не претендует, что overlay уже активен; скрытого
  редактирования профилей не делает. Если Task 1 подтвердит безопасный drop-in
  (`OPENCODE_CONFIG_DIR`), активация сведётся к копированию файла в директорию;
- **precedence-оговорка (codex CRITICAL 3):** `custom` ниже `project` — при
  конфликтующем project-конфиге overlay может не примениться; это документируется, и
  installer это озвучивает;
- **fallback** (agents-only): не активировать overlay — тогда `build`/`plan` останутся
  в цикле и `guard-normal` не станет дефолтом (честная оговорка в README).

`verify.yml`: `on: pull_request` → setup-python → `python -m unittest discover tests` +
**`bash tests/test_install.sh`** + `shellcheck install.sh tests/test_install.sh`. Никакой
записи в `main`, `contents: write` не нужен.

## Implementation Steps

### Task 1: Spike — подтверждение оставшихся допущений (hard gate)

> На машине с установленным opencode. Результаты — в этот план (⚠️/➕). Задачи с
> написанием агентов (Task 3+) НЕ начинать, пока не закрыты пункты-гейты.

**Files:** Modify `docs/plans/20260712-opencode-guardrails.md`.

- [x] **(gate)** `disable: true` для встроенных `build`/`plan`: точный синтаксис; они
      реально уходят из Tab-цикла; `default_agent: guard-normal` применяется
      → FINDING: синтаксис — top-level ключ `agent` (НЕ `mode`):
      `{"agent": {"build": {"disable": true}, "plan": {"disable": true}}}`. Проверено:
      `opencode agent list` — build/plan исчезают из списка primary-агентов (значит и из
      Tab-цикла — они больше не selectable). `"default_agent": "guard-normal"` применяется
      (виден в `opencode debug config`). Визуальный Tab-cycle headless не воспроизвести —
      отсутствие в `agent list` = strong proxy; финальная визуальная проверка остаётся
      runtime smoke-gate'ом Task 8. Примечание: `agent list` показывает служебные primary
      `compaction`/`summary`/`title` — это внутренние агенты, не часть пользовательского
      Tab-цикла.
- [x] **(gate, codex CRITICAL 1)** позиция top-level `"*"`: подтвердить, что он должен
      идти ПЕРВЫМ в `permission` (иначе затирает блоки `read`/`bash`); проверить на живом
      конфиге, что при `"*"`-первым floor `read`/`bash` и `ask` для
      `external_directory`/`doom_loop` не затираются
      → FINDING: ПОДТВЕРЖДЕНО. `evaluate()` = `rulesets.flat().findLast(rule =>
      Wildcard.match(permission, rule.permission) && Wildcard.match(pattern, rule.pattern))`,
      дефолт `ask` (`permission/index.ts`, `permission.ts` V2 — обе версии идентичны).
      Порядок правил = insertion order из JSON/YAML (Effect parse `propertyOrder: "original"`).
      Эмпирически (`debug agent` resolved-list): при `"*"` ПОСЛЕ `read` правило `* * allow`
      оказывается после `read .env deny` и, т.к. `findLast` матчит и permission-ключ (`*`
      матчит `read`), затирает deny → allow. Значит `"*"` ОБЯЗАН быть ПЕРВЫМ. Наш config
      **дописывается ПОСЛЕ** встроенных defaults (last-match-wins работает и относительно
      встроенных правил).
- [x] **(gate)** overlay через `OPENCODE_CONFIG`: слой **добавляется** (не подменяет
      global)? Если рискованно — проверить `OPENCODE_CONFIG_DIR` drop-in. Зафиксировать
      безопасный способ подключения для `install.sh`
      → FINDING: `OPENCODE_CONFIG` **МЕРДЖИТ** (добавляет слой над global; global
      по-прежнему применяется — проверено: global `default_agent`/`disable` сохраняются +
      overlay-агент добавляется). `OPENCODE_CONFIG_DIR` тоже мерджит И является **чистым
      single-dir drop-in**: указывает на директорию, из которой грузятся И `opencode.json`,
      И `agent/*.md` из под-папки `agent/` (проверено). **РЕКОМЕНДАЦИЯ для install.sh:
      OPENCODE_CONFIG_DIR** — installer кладёт overlay + агентов в одну директорию, юзер
      экспортирует ОДНУ env-переменную. Оба варианта всё равно требуют выставить env var
      (в родительский shell из скрипта не пробросить) — installer печатает `export`.
- [x] **(gate, codex CRITICAL 3 + plan-review Important 1)** прогнать конфликтные сценарии
      global/custom/project: переопределяет ли существующий project-`opencode.json` наш
      `default_agent`/`disable` (`custom` ниже `project`). **Решить конкретный механизм с
      достаточным приоритетом** (напр. запись overlay в project-слой при `--project`, или
      семантика `OPENCODE_CONFIG_DIR`) ИЛИ, если надёжного нет, — зафиксировать ограничение
      **в Overview заметно** (не только в выводе installer), т.к. от этого зависит
      заголовочное поведение продукта
      → FINDING: ПОДТВЕРЖДЕНО precedence **project > custom (OPENCODE_CONFIG/DIR) > global**.
      Эмпирически: project-`opencode.json` (в корне `./opencode.json` ИЛИ `./.opencode/opencode.json`
      — оба = project-слой) ПЕРЕОПРЕДЕЛЯЕТ наш `default_agent` И возвращает build/plan
      (его `disable:false` побеждает). Env-based способа перебить project-слой НЕТ. Единственный
      механизм с достаточным приоритетом — **писать В project-слой** (мерджить overlay в
      `./.opencode/opencode.json` пользователя при `--project`). ⚠️ Ограничение реально —
      зафиксировать заметно в Overview/README (уже отражено в Overview-оговорке).
- [x] **(codex MAJOR 2)** формат frontmatter: **предпочесть формат со stdlib-парсером** —
      TOML (`tomllib`, read-only, stdlib 3.11+) или JSON (`json`), если opencode их
      принимает; если только YAML — описать **минимальный** parser нашего фиксированного
      frontmatter (не тащить `pyyaml`). Зафиксировать выбор
      → FINDING: TOML (`+++`) НЕ поддерживается (агент грузится, но frontmatter игнорируется —
      mode фолбэчит на `all`). YAML — да. **JSON-объект внутри `---`-fences РАБОТАЕТ**
      (JSON — подмножество YAML, парсер opencode принимает; проверено с multi-line
      pretty-printed JSON — `mode: primary` и `permission` применяются корректно).
      **ВЫБОР: писать frontmatter как JSON-объект между `---`** — opencode парсит как YAML,
      а наши тесты извлекают текст между fences и парсят stdlib-`json` (нулевая зависимость,
      без минимального YAML-парсера). ➕ Это упрощает Task 3/4 (валидатор = `json.loads`).
- [x] форма пути в `read`-engine (относит. к worktree? абсолютные?) — под матрицу путей;
      уточнить, нужны ли absolute-паттерны
      → FINDING: `read.ts` передаёт в permission `path.relative(instance.worktree, filepath)` —
      **путь ОТНОСИТЕЛЬНО worktree** (напр. `.env`, `nested/.env`, `src/main.py`).
      Absolute-паттерны для внутри-репных файлов НЕ нужны. ⚠️ **КЛЮЧЕВАЯ КОРРЕКЦИЯ:**
      `Wildcard.match` = `new RegExp("^"+escaped+"$", "s")`, где `*`→`.*`, `?`→`.`, флаг
      `s` (dotall). Значит **`*` ПЕРЕСЕКАЕТ `/`** (в отличие от прежнего picomatch-допущения).
      → ПАРНЫЕ root+nested паттерны (`*.pem` + `**/*.pem`) **ИЗБЫТОЧНЫ**: одного `*.pem`
      (`^.*\.pem$`) хватает на `app.pem` И `nested/app.pem`. Литеральные паттерны без `*`
      (`.env`, `credentials`, `secrets`) матчат ТОЛЬКО точную относительную строку
      (root-уровень); для любой глубины нужен ведущий `*` (`*.env`, и т.п.). `/` в паттерне
      НЕ экранируется — остаётся литеральным; матч — полная строка, anchored `^...$`.
- [x] уважают ли `grep`/`glob` встроенный `.env`-deny (закрывает ли это дыру на `normal`)
      → FINDING: НЕТ. `grep.ts`/`glob.ts` вызывают `ctx.ask` с СОБСТВЕННЫМ permission-ключом
      (`grep`/`glob`) и `patterns: [params.pattern]` — матч идёт по ПОИСКОВОМУ паттерну, НЕ
      по путям файлов. `read`-овый `.env`-deny к ним не применяется. ⚠️ Дыра остаётся на
      `normal`/`loose` — документировать (footnote ‡ в таблице верна).
- [x] распарсенные формы bash-команд: как записать `rm`, `git push`, `git reset --hard`,
      `curl … | sh` в permission, чтобы матчер их ловил; какие обходы остаются (в README)
      → FINDING: в 1.17.18 bash **матчит ВСЮ строку команды** — `bash.ts` (core, PermissionV2)
      передаёт `resources: [input.command]` (сырая команда целиком). Parser-based reduction
      (tree-sitter) ЕЩЁ НЕ портирован (`// TODO: Port tree-sitter bash` в `bash.ts`). Матч —
      тем же `Wildcard`-regex по полной строке. Формы для floor: `git push*`
      (или `git push *` → правило «trailing ` *` → `( .*)?`» матчит и `git push`, и
      `git push origin main`), `rm *`, `git reset --hard*`, `curl *| sh` / `*| sh`
      (`|` экранируется в regex). Обходы (граница модели A): цепочки/переменные
      (`c=rm; $c x`, `echo x|sh`), любые формы, не начинающиеся с литерального префикса.
- [x] подтвердить: `.env`-deny + наши deny-секреты (root+nested) не конфликтуют; carve-out
      `*.env.example`/`**/*.env.example` работает (last-match-wins)
      → FINDING: конфликта нет. ⚠️ **КОРРЕКЦИЯ:** встроенный env-default — НЕ `deny`, а
      `ask`: resolved-list build/любого агента = `read *.env → ask`, `read *.env.* → ask`,
      `read *.env.example → allow`. Наши deny дописываются ПОСЛЕ → перебивают на `deny`.
      Carve-out `*.env.example` (allow), стоящий ПОСЛЕДНИМ, перебивает deny (last-match,
      проверено в resolved-list). Литерал `.env` (deny, `^\.env$`) НЕ ловит `.env.example`
      (точный матч). ➕ Т.к. `*` пересекает `/`, `**/*.env.example` избыточен — хватает
      `*.env.example`.
- [x] проверить, что `catch-all "*"` покрывает `task`/`external_directory`/`doom_loop`
      → FINDING: `task` — ДА, покрыт `"*"` (в resolved-list НЕТ отдельного `task`-правила →
      управляется top-level `"*"`). `external_directory`/`doom_loop` — opencode ВСТРАИВАЕТ
      для них собственные явные правила (ПОСЛЕ top-level `"*"`, вкл. allow для tool-output/
      `/tmp/opencode`). Значит один `"*"` их НЕ контролирует (встроенные правила перебьют) —
      их НАДО задавать явно (как в формате плана: `external_directory: "ask"`, `doom_loop:
      "ask"` дописываются последними и перебивают). ➕ Также существуют ключи `list`, `lsp`,
      `skill`, `todowrite`, `question` (см. схему `v1/config/permission.ts`) — тоже покрываются
      `"*"`, если не заданы явно.
- [x] записать версию opencode (min + проверенная) и все корректировки в план
      → FINDING: **min supported = verified = 1.17.18** (binary `/home/mgcom/.opencode/bin/opencode`;
      исходники сверены с тегом `v1.17.18` репо `sst/opencode`). Сводка корректировок ниже.

**➕ Корректировки плана по итогам Task 1 (учесть в Task 3/4):**
1. ⚠️ **`*` ПЕРЕСЕКАЕТ `/`** (matcher = custom regex `*`→`.*` dotall, НЕ picomatch). Вся
   логика «`*` не пересекает `/` → ПАРНЫЕ root+nested» — ОТМЕНЯЕТСЯ. Floor можно
   значительно упростить: один `*.pem`/`*.key`/`*.env` покрывает любую глубину. Матрица
   путей в Testing Strategy и формат агента в Technical Details — переписать под это
   (убрать `**/`-дубли; для секрет-имён без расширения использовать ведущий `*`, но следить
   за anchored-негативами: `*credentials*` даст ложный deny на `credentials-guide.md` —
   держать якорную форму `*/credentials`+`credentials` или `*.credentials`-подобную; финальный
   список — в Task 4 с прогоном через `resolve()` под ЭТУ regex-семантику).
2. ⚠️ Встроенный env-default = **`ask`**, не `deny` (Context-раздел «`.env` — `deny` по
   умолчанию» — неверно). Наш `deny` его усиливает.
3. ➕ Frontmatter = **JSON-объект между `---`** (stdlib `json`); отдельный YAML-парсер не нужен.
4. ➕ Install: **`OPENCODE_CONFIG_DIR`** — single-dir drop-in (overlay + `agent/`), одна env var.
5. ⚠️ Precedence: project-конфиг перебивает overlay — ограничение реально; для гарантии при
   `--project` мерджить в `./.opencode/opencode.json`.
6. ⚠️ bash матчит ВСЮ строку (parser не портирован) → формы `git push*`/`rm *`/`*| sh`.
7. ➕ `resolve()`-helper в тестах должен моделировать ИМЕННО этот matcher: анкор `^...$`,
   `*`→`.*` (пересекает `/`), `?`→`.`, dotall, экранирование `[.+^${}()|[\]\\]`, правило
   «trailing ` *`→`( .*)?`», last-match-wins по insertion order, дефолт `ask`.

### Task 2: Репо-скелет

**Files:** Create `LICENSE`, `.gitignore`, `tests/__init__.py`.

- [x] git-репозиторий инициализирован (уже есть remote)
- [x] `LICENSE` — MIT
- [x] `.gitignore` — `__pycache__/`, `*.pyc`, `.venv/` (без `.pytest_cache/` — используем
      только `unittest`, codex MINOR 1)
- [x] `tests/__init__.py` (пакет для `unittest discover`)
- [x] `AGENTS.md`/`CLAUDE.md`/`CONTEXT.md`/`docs/adr/0001-*` уже на месте
- [x] `python -m unittest discover tests` — 0 тестов, без ошибок сбора

### Task 3: Тесты артефакта — сначала (tests-first, codex MAJOR 1)

**Files:** Create `tests/test_agents.py`.

> Пишем тесты ДО агентов (Task 4), чтобы соблюсти заявленную дисциплину. `resolve()` —
> **документированный helper внутри этого файла** (модель семантики opencode из Task 1,
> НЕ авторитетная реализация; отдельный модуль убран — codex over-engineering: потребитель
> один). Его собственные юнит-тесты зелёные сразу; артефактные тесты красные до Task 4.

- [x] `resolve(read_block, path)` helper: last-match-wins по glob'ам, `*` не пересекает `/`;
      с явной пометкой-докстрингом «модель, не авторитет»
- [x] юнит-тесты `resolve()` (зелёные сразу): порядок правил, carve-out перебивает deny,
      root vs nested (`*.pem` не ловит `nested/x.pem` и наоборот), **carve-out dotfile**
      (`*.env.example` перекрывает `.env*`-deny для литерала `.env.example` — leading-`*`
      матчит имя с точки; подтвердить в Task 8 smoke), anchored-негативы
      (`credentials-guide.md`/`secrets-overview.md` НЕ deny)
- [x] инвариант порядка (красный до Task 4): top-level `"*"` ПЕРВЫЙ в `permission`; внутри
      `read`/`bash` `"*"` первым; floor-блок побайтово одинаков во всех трёх `guard-*.md`
- [x] матрица реальных путей через `resolve()` (root+nested+absolute+negative по Testing
      Strategy) — success, когда появятся агенты
- [x] валидатор frontmatter/overlay (способ из Task 1: `tomllib`/`json`/минимальный parser);
      error-кейсы через **`assertRaises`/отрицательный результат** (validator ОТКЛОНЯЕТ битый
      вход — тест не падает сам, codex MINOR 2)
- [x] прогон `python -m unittest discover tests`: `resolve`-юниты зелёные, артефактные —
      красные (ожидаемо до Task 4)

### Task 4: Три агента + overlay (делают тесты зелёными)

**Files:** Create `agents/guard-strict.md`, `agents/guard-normal.md`,
`agents/guard-loose.md`, `opencode.json`.

- [x] написать три `.md` по таблице/формату (top-level `"*"` ПЕРВЫМ; в `read` — `"*"`,
      ask-hidden, deny-секреты **root+nested**, carve-out последним; floor **идентичен**
      во всех трёх)
- [x] `opencode.json` overlay: `default_agent: guard-normal` + `disable` build/plan
- [x] короткая инструкция в теле каждого агента (только про уровень подтверждений)
- [x] frontmatter/JSON валидны выбранным в Task 1 способом (не `python -m json.tool` для
      YAML — у stdlib нет YAML-парсера, codex MAJOR 2)
- [x] прогон `python -m unittest discover tests` — **ВСЕ зелёные** (инвариант + матрица +
      валидатор + `resolve`-юниты)

### Task 5: install.sh + тесты + подключение overlay

**Files:** Create `install.sh`, `tests/test_install.sh`.

- [x] копирует `agents/*.md` в `~/.config/opencode/agents/` (`--project` → `.opencode/agents/`)
      и кладёт overlay-файл в известное место
      → сделано: агенты копируются в `agent/`-подпапку (не `agents/`) — подтверждено
      скретч-проверкой: opencode 1.17.18 грузит агентов из `agent/` (singular) и в глобальном
      конфиге, и в `OPENCODE_CONFIG_DIR`. Global: агенты → `${XDG_CONFIG_HOME:-~/.config}/opencode/agent/`
      (всегда грузятся → работает agents-only fallback), overlay → drop-in `…/opencode-guardrails/`.
      `--project`: агенты → `./.opencode/agent/`, overlay → `./.opencode/opencode.json`.
- [x] активация overlay (codex MAJOR 3): для `OPENCODE_CONFIG` скрипт **печатает точную
      команду** (`export …` + как добавить в профиль), НЕ претендуя, что уже активировал
      (env var в родительский shell из скрипта не пробросить); для `OPENCODE_CONFIG_DIR`
      (если Task 1 подтвердил) — просто копирует файл в drop-in-директорию. Чужой
      `opencode.json` НЕ правит; скрытого редактирования профилей нет
      → сделано: global-режим печатает `export OPENCODE_CONFIG_DIR="…"` + `>> ~/.bashrc`-подсказку,
      явно оговаривает, что профиль НЕ правится и overlay ещё не активен. `--project` пишет overlay
      в project-слой (активен без env var).
- [x] печатает precedence-оговорку: project-конфиг может переопределить overlay (CRITICAL 3)
- [x] fallback agents-only задокументирован в выводе (build/plan останутся)
- [x] идемпотентность; не перезаписывать чужие одноимённые `.md` без `--force`; понятный вывод
      → повторный запуск: `unchanged:`; чужой отличающийся файл без `--force` → `refused:` + exit 3,
      файл не тронут; `--force` перезаписывает.
- [x] `tests/test_install.sh` success: чистые `HOME`/project во временных каталогах; оба режима
- [x] `tests/test_install.sh` error: чужой файл без `--force` → отказ; `--force` перезаписывает;
      неизвестный флаг → ненулевой код + usage; отсутствие `agents/` → внятная ошибка
- [x] `shellcheck install.sh` чисто; `bash tests/test_install.sh` — успех
      → shellcheck 0.10.0: 0 warnings; test_install.sh: 25/25 passed; `python3 -m unittest
      discover tests`: Ran 32 OK.

### Task 6: CI — verify.yml (только PR, без записи в main)

**Files:** Create `.github/workflows/verify.yml`.

- [x] `on: pull_request` → setup-python → `python -m unittest discover tests`
      **+ `bash tests/test_install.sh`** (codex CRITICAL 4 — discover shell-тесты не гоняет)
      + `shellcheck install.sh tests/test_install.sh`
- [x] проверка «только stdlib»: тесты идут на чистом setup-python без установки зависимостей
- [x] валидность самого `verify.yml` — доверяем парсеру GitHub Actions при запуске
      (отдельного YAML-линтера не тащим, codex MINOR 3); никакой записи в `main`,
      `contents: write` не требуется

### Task 7: README.md + README_RU.md (двуязычно)

**Files:** Create `README.md` (English), `README_RU.md` (Russian).

- [x] назначение, таблица уровней, floor; **модель угроз — только A** (ссылка на ADR)
- [x] **раздел «Hardening»**: для защиты от вредоносного/injection — запускать opencode в
      OS-sandbox (композиция); guardrails — не security-граница
- [x] установка: **основной путь — `install.sh` + overlay через `OPENCODE_CONFIG`**;
      fallback agents-only (с оговоркой про build/plan)
- [x] раздел «Совместимость»: min + проверенная версии opencode (Task 1)
- [x] раздел «Известные ограничения»: grep/glob, bash-обходы, `--auto`/`always`
- [x] `README_RU.md` — перевод, те же разделы; взаимные ссылки вверху
- [x] `tests/test_readme_links.py` — ссылки/пути в обоих README резолвятся (success + error-фикстура)
- [x] `python -m unittest discover tests` — успех

### Task 8: Приёмка — включая ОБЯЗАТЕЛЬНЫЙ runtime smoke-gate

> Правка codex CRITICAL 5: раньше живая проверка готовых артефактов была необязательным
> post-completion. Теперь это acceptance-gate: Python-`resolve()` — лишь модель.

- [x] три уровня-агента; floor `read`: секреты → `deny` (переживает `--auto`), прочие
      скрытые → `ask` (условно) — подтверждено тестом (`Ran 37 OK`; `deny`-переживает-`--auto`
      — по конструкции opencode: `--auto` гасит только `ask`, Task 1)
- [x] границы best-effort (grep/glob, bash) явно задокументированы; критерии не обещают
      того, чего нет; модель угроз A зафиксирована (ADR + README) → сверено:
      README «Known limitations» (grep/glob не уважают `read`-deny; bash whole-string
      best-effort; `--auto`/`always` гасят ask-слой; project-precedence) + «Threat model —
      the careless agent only»/«Hardening»; `docs/adr/0001-*` — Decision «Defend against A only».
- [x] артефакт — чистые данные, ставится `install.sh` без зависимостей (три `.md` +
      `opencode.json`; installer только копирует файлы; ноль pip-зависимостей)
- [x] `verify.yml` гоняет `unittest` + `bash test_install.sh` + shellcheck на PR; записи в
      `main` нет → сверено: `on: pull_request`, `permissions: contents: read`, три шага
      (unittest / `bash tests/test_install.sh` / `shellcheck install.sh tests/test_install.sh`).
- [x] полный прогон: `python3 -m unittest discover tests` (Ran 37 OK) +
      `bash tests/test_install.sh` (25 passed)
- [x] **(GATE) runtime smoke на живом opencode** (мин. одна подтверждённая версия): установить
      `install.sh` + активировать overlay; проверить вживую — обычный `read` (allow),
      `read .env` (deny), `read .gitignore` (ask), carve-out `.env.example` (allow),
      dangerous bash (`git push`/`rm` → ask), `default_agent: guard-normal`, Tab-цикл без
      `build`/`plan`. Расхождения с моделью `resolve()` → чинить агентов и матрицу
      → SMOKE (opencode 1.17.18, `/home/mgcom/.opencode/bin/opencode`, изолированный
      `HOME`/`XDG_CONFIG_HOME` в scratchpad): `bash install.sh` (global) разложил агентов в
      `…/opencode/agent/` + overlay в drop-in; активирован `OPENCODE_CONFIG_DIR`.
      Проверял РЕАЛЬНЫЕ резолвнутые правила opencode через `opencode debug agent
      <guard-*>` (даёт flat ruleset после мерджа слоёв и встроенных правил) и прогонял их
      через matcher, **побайтово снятый из бинаря 1.17.18** (`pattern.replaceAll("\\","/")
      .replace(/[.+^${}()|[\]\\]/g,"\\$&").replace(/\*/g,".*").replace(/\?/g,".")`;
      trailing `" .*"→"( .*)?"`; `new RegExp("^"+l+"$","s")`; `findLast`, дефолт `ask`) —
      т.е. чужой конфиг-мердж делал сам opencode, я лишь применил его же чистую matcher-
      функцию. 26/26 проб СОШЛИСЬ с моделью (нулём расхождений, правки агентов/тестов НЕ
      потребовались):
      guard-normal `read`: `src/main.py`→allow, `.env`→deny, `nested/.env`→deny,
      `.gitignore`→ask, `.env.example`→allow (carve-out бьёт deny), `credentials-guide.md`→
      **allow** (не deny), `.aws/credentials`→deny, `secrets-overview.md`→allow,
      `server.pem`→deny, `nested/app.key`→deny, `id_rsa`→deny;
      guard-normal `bash`: `git push`/`git push origin main`/`rm foo`→ask, `ls -la`→ask;
      guard-strict: `read src/main.py`→ask, `.env`→deny, `grep`→ask;
      guard-loose: `read src/main.py`→allow, `.env`→deny, `.env.example`→allow, `.gitignore`→
      ask, `bash ls -la`→allow, `git push`/`rm foo`→ask, `edit`→allow.
      `opencode agent list`: primary = guard-strict/normal/loose (+ внутренние
      compaction/summary/title) — **build/plan ОТСУТСТВУЮТ** (ушли из Tab-цикла).
      `opencode debug config`: `default_agent = guard-normal`. Frontmatter (JSON-в-`---`)
      распарсился (иначе `debug agent` не отдал бы permission-правила).
      ⚠️ **Прокси**: живой Tab-keypress-цикл и интерактивные `ask`/`--auto`-промпты в TUI
      headless не автоматизируются (`run` требует provider-auth) — верифицировано по прокси
      (отсутствие build/plan в `agent list` + резолвнутые правила из `debug agent`), как и
      предусмотрено Task 1.

### Task 9: [Final] Архивирование

**Files:** —

- [x] переместить план в `docs/plans/completed/` (move deferred to harness after review phases — per exec process)
- [x] финальный прогон `python -m unittest discover tests` + `bash tests/test_install.sh`
      ПОСЛЕ перемещения (в т.ч. `test_readme_links` — пути не сломались)
      → финальный прогон green: `python3 -m unittest discover tests` = Ran 37 OK
      (incl. `test_agents`, `test_readme_links`); `bash tests/test_install.sh` = 25 passed, 0 failed.

## Post-Completion

*Ручные/внешние действия — без чекбоксов.*

> Обязательный runtime smoke — теперь **acceptance-gate в Task 8**, не здесь (codex CRITICAL 5).

**Дополнительная проверка (сверх Task 8-gate):**
- прогнать на min И актуальной версиях opencode (Task 1), зафиксировать различия поведения;
- установка сторонним пользователем на его машине (global и `--project` пути).

**Внешние системы:**
- репозиторий на GitHub, включить Actions (для `verify.yml` `contents: write` не нужен);
- опубликовать; при желании — шаблон/релизы.

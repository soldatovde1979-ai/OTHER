// Локальный OpenAI-совместимый прокси к шлюзу OpenCoder с подписью запросов (ed25519-v1).
// Roo Code -> http://127.0.0.1:8787/v1 (любой Bearer-ключ) -> переподпись -> https://code.accelstacks.com/gw/v1
// Запуск: node gw-proxy.mjs  (или gw-proxy.cmd — проверит окружение и при необходимости поставит Node)
import { createHash, createPrivateKey, sign, randomBytes } from 'node:crypto';
import { readFileSync, existsSync } from 'node:fs';
import http from 'node:http';
import { Readable } from 'node:stream';
import { execSync, spawnSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';

const SCRIPT_PATH = fileURLToPath(import.meta.url);

const GW_BASE = 'https://code.accelstacks.com';
const CRED_PATH = process.env.LOCALAPPDATA + '\\OpenCoder\\cc-web-credentials.json';
const CLI_PATH = 'C:\\OpenCoder\\cli.js';
const PORT = Number(process.env.GW_PROXY_PORT || 8787);
// Сколько ждать заголовков от шлюза. Стриминг ответа после заголовков не ограничен.
const UPSTREAM_TIMEOUT_MS = Number(process.env.GW_PROXY_TIMEOUT_MS || 60000);
const BASE_URL = `http://127.0.0.1:${PORT}/v1`;
const PROFILES = [
  { name: 'OC', model: 'flash', note: 'быстрая модель' },
  { name: 'OC PRO', model: 'pro', note: 'тяжёлая модель' },
  { name: 'OC PRO+', model: 'pro', note: 'то же, Reasoning Effort = High' },
];
const ROO_EXT_ID = 'rooveterinaryinc.roo-cline';
const ZOO_EXT_ID = 'zoocodeorganization.zoo-code'; // форк Roo — тот же формат конфига

const ok = (s) => `\x1b[32m[OK]\x1b[0m ${s}`;
const warn = (s) => `\x1b[33m[!!]\x1b[0m ${s}`;
const info = (s) => `     ${s}`;

let BUILD_SHA = '';
try {
  BUILD_SHA = createHash('sha256').update(readFileSync(CLI_PATH)).digest('hex');
} catch {} // cli.js не найден — допустимо, шлюз принимает пустой x-ccw-build
const creds = () =>
  JSON.parse(readFileSync(CRED_PATH, 'utf8')).credentials['https://code.accelstacks.com/gw'];

function signedHeaders(cred, urlStr, method, bodyBytes) {
  const url = new URL(urlStr);
  const timestamp = String(Math.floor(Date.now()));
  const nonce = randomBytes(24).toString('base64url');
  const contentSha = createHash('sha256').update(bodyBytes).digest('base64url');
  const canonical = [
    'CCW-OPENCODER-REQUEST',
    '1',
    cred.tokenId,
    timestamp,
    nonce,
    method,
    url.pathname + url.search,
    contentSha,
    BUILD_SHA,
  ].join('\n');
  const key = createPrivateKey({
    key: Buffer.from(cred.requestSigningPrivateKey, 'base64url'),
    format: 'der',
    type: 'pkcs8',
  });
  const signature = sign(null, Buffer.from(canonical, 'utf8'), key).toString('base64url');
  return {
    authorization: 'Bearer ' + cred.accessToken,
    'x-ccw-request-version': '1',
    'x-ccw-request-timestamp': timestamp,
    'x-ccw-request-nonce': nonce,
    'x-ccw-content-sha256': contentSha,
    'x-ccw-request-signature': signature,
    'x-ccw-build': BUILD_SHA,
  };
}

async function readBody(req) {
  const chunks = [];
  for await (const c of req) chunks.push(c);
  return Buffer.concat(chunks);
}

/* ================= Preflight: проверки окружения ================= */

function checkNode() {
  const [maj] = process.versions.node.split('.').map(Number);
  if (maj < 18) {
    console.warn(warn(`Node.js ${process.versions.node} — староват, нужен >= 18.`));
  } else {
    console.log(ok(`Node.js ${process.versions.node}`));
  }
}

function checkCredentials() {
  if (!existsSync(CRED_PATH)) {
    console.warn(warn('Креденшалы OpenCoder не найдены: ' + CRED_PATH));
    console.warn(info('→ Запусти и войди в OpenCoder CLI, затем перезапусти прокси.'));
    process.exit(1);
  }
  try {
    const c = creds();
    if (!c.requestSigningPrivateKey) throw new Error('legacy credential без ключа подписи');
    console.log(ok('Креденшалы OpenCoder найдены (managed device)'));
  } catch {
    console.warn(warn('Креденшалы устарели или повреждены. Переустанови OpenCoder с дашборда.'));
    process.exit(1);
  }
}

function checkVscodeRoo() {
  let codeCli = null;
  for (const c of ['code', 'code.cmd']) {
    try {
      execSync(`where ${c}`, { stdio: 'pipe' });
      codeCli = c;
      break;
    } catch {}
  }
  if (!codeCli) {
    console.warn(warn('VS Code / CLI "code" не найден — поставь VS Code и расширение Roo Code.'));
    return;
  }
  let list = '';
  try {
    list = execSync(`${codeCli} --list-extensions`, { encoding: 'utf8', timeout: 30000 });
  } catch {
    console.warn(warn('Не удалось выполнить "code --list-extensions" — пропускаю проверку Roo.'));
    return;
  }
  const exts = list.toLowerCase();
  if (exts.includes(ROO_EXT_ID.toLowerCase())) {
    console.log(ok('Roo Code установлен'));
    checkRooProfiles('RooVeterinaryInc.roo-cline').catch(() => {});
  } else if (exts.includes(ZOO_EXT_ID)) {
    console.log(ok('Обнаружен Zoo Code (форк Roo Code) — настройка профилей та же'));
    checkRooProfiles(ZOO_EXT_ID).catch(() => {});
  } else {
    console.warn(warn('Roo Code не установлен. Устанавливаю...'));
    const r = spawnSync(codeCli, ['--install-extension', ROO_EXT_ID, '--force'], {
      encoding: 'utf8',
      timeout: 120000,
    });
    if (r.status === 0) console.log(ok('Roo Code установлен — перезапусти VS Code, если он был открыт'));
    else {
      console.warn(info(`Автоматика не прошла (код ${r.status}). Вручную: ${codeCli} --install-extension ${ROO_EXT_ID}`));
      if (r.stderr) console.warn(info(String(r.stderr).trim().slice(0, 200)));
    }
  }
}

async function checkRooProfiles(stateKey) {
  // Профили Roo хранятся в state.vscdb (читаем; сами ключи шифруются VS Code — их не трогаем)
  const dbPath = process.env.APPDATA + '\\Code\\User\\globalStorage\\state.vscdb';
  if (!existsSync(dbPath)) return;
  try {
    const { DatabaseSync } = await import('node:sqlite');
    const db = new DatabaseSync(dbPath, { readOnly: true });
    const row = db.prepare("SELECT value FROM ItemTable WHERE key = ?").get(stateKey);
    db.close();
    const state = row ? JSON.parse(row.value) : {};
    const names = (state.listApiConfigMeta || []).map((p) => p.name);
    const missing = PROFILES.filter((p) => !names.includes(p.name));
    if (missing.length === 0) {
      console.log(ok('Профили Roo настроены: ' + PROFILES.map((p) => p.name).join(', ')));
    } else {
      console.warn(warn('В Roo нет профилей: ' + missing.map((p) => p.name).join(', ')));
      console.warn(info('Настройка — Roo Code → Settings → Provider → OpenAI Compatible:'));
      for (const p of PROFILES) {
        console.warn(
          info(
            `• "${p.name}" — Base URL: ${BASE_URL} | API Key: local | Model: ${p.model} (${p.note})`
          )
        );
      }
    }
  } catch {
    console.warn(info('Профили Roo не проверены (нет node:sqlite или база занята) — не критично.'));
  }
}

function checkAutostart() {
  let enabled = false;
  try {
    const out = execSync('schtasks /query /tn "gw-proxy"', { encoding: 'utf8', stdio: 'pipe' });
    enabled = out.includes('gw-proxy');
  } catch {}
  console.log(info('')); // пустая строка-разделитель
  if (enabled) {
    console.log(ok('Автозапуск: включён (задача планировщика "gw-proxy")'));
    console.warn(info('Выключить: schtasks /delete /tn "gw-proxy" /f'));
  } else {
    console.warn(warn('Автозапуск: не настроен — прокси надо запускать вручную.'));
    console.warn(info('Включить: schtasks /create /tn "gw-proxy" /tr "node ' + SCRIPT_PATH + '" /sc onlogon /rl limited /f'));
    console.warn(info('Или ярлык на этот файл в shell:startup'));
  }
}

/* ================= HTTP-сервер ================= */

const server = http.createServer(async (req, res) => {
  try {
    const body = await readBody(req);
    const upstreamUrl = GW_BASE + '/gw' + req.url; // /v1/... -> /gw/v1/...
    const method = req.method.toUpperCase();
    const doFetch = (cred) => {
      // Тайм-аут действует только до получения заголовков: зависший апстрим
      // отдаёт клиенту 502 вместо вечного ожидания. Стриминг тела не ограничен.
      const ac = new AbortController();
      const timer = setTimeout(() => ac.abort(), UPSTREAM_TIMEOUT_MS);
      return fetch(upstreamUrl, {
        method,
        headers: {
          ...signedHeaders(cred, upstreamUrl, method, body),
          ...(body.length && { 'content-type': req.headers['content-type'] || 'application/json' }),
          ...(req.headers.accept && { accept: req.headers.accept }),
        },
        ...(body.length && { body }),
        signal: ac.signal,
      }).finally(() => clearTimeout(timer));
    };

    let upstream = await doFetch(creds());
    if (upstream.status === 401) {
      // креденшал мог ротироваться — перечитать и переподписать один раз
      upstream = await doFetch(creds());
    }

    const headers = { 'content-type': upstream.headers.get('content-type') || 'application/json' };
    if (upstream.headers.get('cache-control')) headers['cache-control'] = upstream.headers.get('cache-control');
    res.writeHead(upstream.status, headers);
    if (upstream.body) Readable.fromWeb(upstream.body).pipe(res);
    else res.end();
  } catch (e) {
    res.writeHead(502, { 'content-type': 'application/json' });
    res.end(JSON.stringify({ error: { message: String(e), type: 'proxy_error' } }));
  }
});

/* ================= Запуск ================= */

console.log('\n=== gw-proxy: проверка окружения ===');
checkNode();
checkCredentials();
checkVscodeRoo();
checkAutostart();

server.listen(PORT, '127.0.0.1', () => {
  console.log('\n=== gw-proxy: запущен ===');
  console.log(info(`Адрес для Roo / клиентов: ${BASE_URL}`));
  console.log(info(`Модели: ${PROFILES.map((p) => `${p.name} = ${p.model}`).join(' | ')}`));
  console.log(info('Останов: Ctrl+C'));
});

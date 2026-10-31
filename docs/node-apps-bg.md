# Отделен Node.js проект с по един контейнер за всеки модул

**Статус: проектно ръководство.** Операторът стартира примерните `gaz` и `mas` във VM; публичните маршрути все още предстои да се проверят. [Работещите учебни приложения](../example-applications/README.md) са в това хранилище; за реално приложение използвай отделен проект. Тук `api.example.com` и имената на папките са условни данни. Истински домейн, облачни имена, IP адреси и `.env` стойности остават локално, извън Git.

## Какво изграждаме

```text
клиент → Cloudflare → Caddy (инфраструктурен проект)
                         ├─ /gaz и /gaz/* → gaz:8080 (Node контейнер)
                         └─ /mas и /mas/* → mas:8081 (Node контейнер)
```

При реално внедряване Node кодът и неговият `compose.yaml` живеят в **отделен проект**; примерите тук са учебен шаблон. Caddy остава в този инфраструктурен проект. Двата Compose проекта споделят една предварително създадена Docker мрежа. В Caddy контейнера `localhost:8080` означава **самия Caddy контейнер**, затова upstream адресите са имената на Node услугите `gaz:8080` и `mas:8081`. Портовете на Node контейнерите **не се публикуват** към VM или интернет. [Docker обяснява DNS имената и външните мрежи между Compose проекти](https://docs.docker.com/compose/how-tos/networking/).

Отделните контейнери позволяват да обновим или рестартираме `gaz`, без да прекъсваме `mas`. Двата контейнера все пак споделят ресурса на една малка VM; преди още услуги измерваме RAM и CPU. Всеки плъгин е изпълним код и се приема само от контролиран източник.

## 1. Еднократна промяна в инфраструктурния проект

1. **На VM:** създай общата мрежа веднъж: `sudo docker network create app-edge`. При повторно внедряване само провери `sudo docker network inspect app-edge`; не изтривай мрежа, към която има контейнери.
2. **В този проект, `compose.yaml`:** добави `gateway` към външната мрежа. Съществуващите `ports`, сертификатните volumes и `restart` остават както са. Пример за новата част:

   ```yaml
   services:
     gateway:
       networks:
         - app_edge

   networks:
     app_edge:
       external: true
       name: app-edge
   ```

   Това е **фрагмент за добавяне** към текущия `compose.yaml`, а не цял файл за замяна. Общото име `app-edge` трябва да е същото и в Node проекта.
3. **В този проект, `Caddyfile`:** запази `/health` и началната страница; добави двата маршрута **преди** общия `handle { respond 404 }`. Пътеки `/gaz` и `/gaz/*` се приемат, а `/gazette` не се прихваща. Caddy маха префикса, така че Node плъгинът вижда `/health` вместо `/gaz/health`:

   ```caddyfile
   {$APP_DOMAIN} {
       handle /health {
           respond "healthy" 200
       }

       @gaz path /gaz /gaz/*
       handle @gaz {
           uri strip_prefix /gaz
           reverse_proxy gaz:8080
       }

       @mas path /mas /mas/*
       handle @mas {
           uri strip_prefix /mas
           reverse_proxy mas:8081
       }

       handle / {
           respond "Cloud VM ready" 200
       }

       handle {
           respond 404
       }
   }
   ```

   [Caddy `handle`](https://caddyserver.com/docs/caddyfile/directives/handle), [`uri strip_prefix`](https://caddyserver.com/docs/caddyfile/directives/uri) и [`reverse_proxy`](https://caddyserver.com/docs/caddyfile/directives/reverse_proxy) описват това поведение. Ако бъдещо приложение генерира абсолютни URL адреси или redirects, настрой и неговия base path; API под папка трябва да бъде тестван и за тези отговори.
4. **В локалния checkout:** `APP_DOMAIN=api.example.com docker compose config --quiet` проверява YAML. Валидирай Caddyfile с Caddy преди качване, после commit/push на ревизираната инфраструктура. Не пускай gateway преди Node контейнерите, за да избегнеш временни `502` отговори.

## 2. Създай отделния проект `node-plugin-server`

Създай отделно хранилище и работна папка за реалния код. [Двата примера тук](../example-applications/README.md) са по-прост начин да упражниш Caddy маршрута и сам да сменяш Node код, без да създаваш production проект. За реалния проект предложената структура е:

```text
node-plugin-server/
├── compose.yaml
├── server.mjs
├── plugins/
│   ├── gaz/
│   │   ├── plugin.json
│   │   └── index.mjs
│   └── mas/
│       ├── plugin.json
│       └── index.mjs
└── .gitignore
```

`plugins/gaz/plugin.json`:

```json
{"name":"gaz","port":8080}
```

`plugins/mas/plugin.json` е същият формат с `"name":"mas"` и `"port":8081`. Един контейнер стартира точно един плъгин, избран чрез `PLUGIN_NAME`. Кодът и manifest-ът на този плъгин се монтират **само в неговия контейнер**. Плъгинът слуша на `0.0.0.0` вътре в контейнера, за да е достъпен от Caddy по Docker мрежата.

Минимален `server.mjs` за двата контейнера:

```js
import { createServer } from 'node:http';
import { readFile } from 'node:fs/promises';

const name = process.env.PLUGIN_NAME;
if (!/^[a-z][a-z0-9-]*$/.test(name ?? '')) throw new Error('Invalid PLUGIN_NAME');

const manifest = JSON.parse(await readFile(new URL('./plugin/plugin.json', import.meta.url), 'utf8'));
if (manifest.name !== name || !Number.isInteger(manifest.port) || manifest.port < 1024 || manifest.port > 65535) {
  throw new Error('Invalid plugin manifest');
}

const { default: handler } = await import(new URL('./plugin/index.mjs', import.meta.url).href);
if (typeof handler !== 'function') throw new Error('Plugin must export a default request handler');

createServer((req, res) => {
  Promise.resolve().then(() => handler(req, res)).catch((error) => {
    console.error(error);
    if (!res.headersSent) res.statusCode = 500;
    if (!res.writableEnded) res.end();
  });
}).listen(manifest.port, '0.0.0.0', () => console.log(`${name} listening on ${manifest.port}`));
```

Примерен `plugins/gaz/index.mjs`; `mas` използва същия договор със свое съдържание:

```js
export default function handle(req, res) {
  res.setHeader('content-type', 'text/plain; charset=utf-8');
  if (req.url === '/health') return res.end('healthy');
  if (req.url === '/' || req.url === '') return res.end('gaz ready');
  res.statusCode = 404;
  res.end('not found');
}
```

Това е малък HTTP договор: плъгинът експортира функция `(req, res)`, обслужва `/health` и връща `404` за непознати пътища. Самият пример няма база, миграции, тайни или npm зависимости. При реални данни добави отделен volume върху монтирания data disk и [съгласуван backup/restore](sqlite-and-backups.md) **преди** внедряване.

`node-plugin-server/compose.yaml`:

```yaml
services:
  gaz:
    image: node:26-alpine
    user: node
    working_dir: /app
    command: [node, server.mjs]
    restart: unless-stopped
    environment:
      PLUGIN_NAME: gaz
    volumes:
      - ./server.mjs:/app/server.mjs:ro
      - ./plugins/gaz:/app/plugin:ro
    networks: [app_edge]

  mas:
    image: node:26-alpine
    user: node
    working_dir: /app
    command: [node, server.mjs]
    restart: unless-stopped
    environment:
      PLUGIN_NAME: mas
    volumes:
      - ./server.mjs:/app/server.mjs:ro
      - ./plugins/mas:/app/plugin:ro
    networks: [app_edge]

networks:
  app_edge:
    external: true
    name: app-edge
```

Няма `ports:`. `node:26-alpine` е пример за актуална към октомври 2026 г. LTS линия; при реално внедряване избери поддържан, обновен образ и запиши точната версия/digest. [Node release status](https://nodejs.org/en/about/previous-releases). В `.gitignore` включи `.env`, `node_modules/` и файлове с данни; не поставяй тайни в `plugin.json`.

## 3. Първо внедряване, в този ред

1. **На VM:** потвърди, че data disk е монтиран и `app-edge` мрежата съществува. Постави **отделния Node проект** в самостоятелна папка, например `/srv/node-plugin-server`. Файловете могат да се доставят като архив; `.git` на VM не е задължителен. Запази правата за четене на `server.mjs` и двата плъгина за потребителя `node` в контейнера.
2. **В папката на Node проекта на VM:** `sudo docker compose config --quiet`, после `sudo docker compose up -d gaz mas` и `sudo docker compose ps`. В логовете трябва да се виждат слушащи 8080 и 8081. Провери поотделно вътре в контейнерите: `sudo docker compose exec -T gaz node -e "fetch('http://127.0.0.1:8080/health').then(async r => console.log(r.status, await r.text()))"` и аналогично за `mas` на 8081. Очакване: `200 healthy` и за двата.
3. **В инфраструктурния проект:** след commit/push на проверените `Caddyfile` и `compose.yaml`, на VM изпълни `sudo /usr/local/sbin/cloud-vm-start`. Този скрипт обновява **само инфраструктурния проект** и пресъздава Caddy. Не копира и не стартира Node проекта.
4. **Отвън през Cloudflare:** провери `curl -i https://api.example.com/gaz/health`, `curl -i https://api.example.com/mas/health`, `curl -i https://api.example.com/health` и един нормален маршрут на всеки плъгин. Очакване: `200 healthy` за двата плъгина, `cf-ray` през Cloudflare, а съществуващият `/health` продължава да работи. `api.example.com/gazette` трябва да остане `404`.
5. **Google Cloud Monitoring:** добави отделни uptime проверки/имейл аларми за `/gaz/health` и `/mas/health`. Сегашният `/health` проверява само Caddy и няма да открие спрян Node контейнер. За същия hostname не се добавят нов DNS запис, Cloudflare custom hostname или публични GCP firewall портове.

## 4. Добавяне или обновяване на плъгин

За вече регистриран маршрут (`gaz` или `mas`): обнови само неговата папка в **Node проекта** и изпълни от неговата VM папка `sudo docker compose up -d --force-recreate gaz` (или `mas`). Провери неговия `/health` и нормална заявка; другият контейнер остава работещ. Не рестартирай целия Docker daemon. Обикновеното `docker compose restart` не прилага промени в Compose environment/configuration; `up --force-recreate` ги прилага. [Docker Compose restart](https://docs.docker.com/reference/cli/docker/compose/restart/).

За **нов публичен път**, например `/foo`:

1. В отделния Node проект добави `plugins/foo/plugin.json` и `index.mjs`, избери свободен вътрешен порт и добави нова Compose услуга `foo` със същия шаблон, `PLUGIN_NAME: foo` и mount на `./plugins/foo`. Commit/достави Node проекта; стартирай само `foo` и провери неговия вътрешен `/health`.
2. В инфраструктурния проект добави `@foo path /foo /foo/*` и `handle @foo { uri strip_prefix /foo; reverse_proxy foo:<port> }` в Caddyfile; провери, commit/push и приложи чрез `cloud-vm-start`. Провери публичния `/foo/health` и добави uptime alert.

Така добавянето е **папка + кратка регистрация в двата Compose/Caddy проекта + пресъздаване на засегнатите контейнери**. Само папка и една променлива не могат да създадат нов Caddy маршрут: Caddy трябва да знае кой път към кой upstream сочи. Ако броят на модулите нарасне, отделна deploy команда може да генерира Compose услуги и Caddy маршрути от manifest-ите; тя трябва да валидира имена/портове, да приложи първо Node, после Caddy, и да поддържа rollback. Засега двата явни маршрута са по-прости за проверка.

## 5. Ограничения преди продукционни данни

- Монтираният plugin код може да се сменя без build, но той е **изпълним код**. Пази го в отделния контролиран проект; не приемай произволни файлове от API заявки. Ако плъгинът има допълнителни npm зависимости или native модули, публикувай версиониран image, вместо да разчиташ само на копиране на папка.
- Сега `node:26-alpine` зарежда `server.mjs` и plugin папките чрез bind mounts. При възстановяване на VM трябва да доставиш отново Node проекта; snapshot на data disk не включва тези source файлове, ако са в `/srv/node-plugin-server` на boot disk. За реална услуга предпочети image, изграден извън малката VM и записан с digest в registry; виж [плана за внедряване](gcp-current-state.md#handoff-първо-внедряване-на-приложението).
- Преди пускане на плъгин с база: монтирай data disk за неговите данни, направи автоматичен съгласуван backup извън VM, провери restore и добави аларма при пропуснат backup. Отделният контейнер сам по себе си не решава възстановяването на данни.
- При проблем върни предишния Node проект или само засегнатия plugin контейнер. При Caddy проблем върни предишния проверен инфраструктурен commit чрез `SOURCE_REF=<пълен-комит> /usr/local/sbin/cloud-vm-start`, след което провери всички публични health пътища. Не сменяй schema само с rollback на image.

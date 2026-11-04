# Нов Node.js app за Cloud VM

Това ръководство е отправна точка за **ново, отделно Git хранилище** с едно Node.js приложение. Примерът използва услуга `foo`, вътрешен порт `8080` и публичен път `/foo`. Замени имената последователно с тези на реалния проект. Няма изискване приложението да е плъгин или да използва конкретен framework.

**Състояние към 4 ноември 2026 г.:** VM, мрежата `app-edge`, Caddy, учебните `gaz` и `mas` и Cloud Logging са потвърдени от оператора. Частен Artifact Registry, image на новото приложение и автоматичен deploy/rollback още не са създадени или проверени. По-долу са примерният договор и ръчният път за първо внедряване; не приемай примерите за вече внедрена автоматизация.

## 1. Договор с инфраструктурата

```text
клиент → Cloudflare → Caddy → app-edge → foo:8080 → Node.js
```

- Приложението слуша на `0.0.0.0:8080` **в контейнера**. Портът не се публикува към VM или интернет; Caddy го достъпва по името `foo` в `app-edge`.
- Caddy приема `/foo` и `/foo/*` и премахва префикса: `/foo/health` пристига в Node като `/health`. Настрой base URL на framework-а, статичните файлове, cookies и redirects за публичния `/foo`, ако приложението ги използва.
- `GET /health` връща `200` и `healthy`, когато приложението е готово да обслужва заявки. При реални зависимости реши кои от тях readiness проверката трябва да включва. Публичният `/health` на Caddy проверява само gateway.
- Логовете отиват към stdout/stderr. На VM отделен Compose overlay включва `gcplogs`; в Logs Explorer контейнерът се намира с `jsonPayload.container.name:"foo"`.
- Публичният маршрут и DNS името в Docker мрежата трябва да са уникални. Ако **заменяме `gaz`**, съществуващият маршрут сочи към `gaz:8080`: запази името на услугата `gaz` и префикса `/gaz`, или отделно промени и приложи Caddy маршрута. Не стартирай две услуги с един и същ мрежов alias.

## 2. Ново хранилище: минимален старт

Примерна структура:

```text
my-node-app/
├── src/server.mjs
├── package.json
├── package-lock.json
├── Dockerfile
├── .dockerignore
├── .gitignore
├── compose.yaml
└── compose.gcp-logging.yaml
```

Минимален `src/server.mjs`:

```js
import { createServer } from 'node:http';

const server = createServer((req, res) => {
  if (req.url === '/health') {
    res.writeHead(200, { 'content-type': 'text/plain; charset=utf-8' });
    return res.end('healthy');
  }
  if (req.url === '/') {
    res.writeHead(200, { 'content-type': 'text/plain; charset=utf-8' });
    return res.end('hello from foo');
  }
  res.writeHead(404);
  res.end('not found');
});

server.listen(8080, '0.0.0.0', () => console.log('foo listening on 8080'));
```

Минимален `package.json`:

```json
{
  "name": "foo",
  "version": "1.0.0",
  "private": true,
  "type": "module",
  "scripts": { "start": "node src/server.mjs" }
}
```

Генерирай и commit-ни lock файла с `npm install --package-lock-only`. Добави истински тестове според поведението на приложението. Избери поддържана Node LTS версия към момента на създаване и я обновявай при security releases; не разчитай безкрайно на примера по-долу. Провери [поддържаните Node версии](https://nodejs.org/en/about/previous-releases).

`Dockerfile`:

```dockerfile
FROM node:24-alpine
WORKDIR /app
COPY --chown=node:node package.json package-lock.json ./
RUN npm ci --omit=dev
COPY --chown=node:node src ./src
USER node
EXPOSE 8080
CMD ["node", "src/server.mjs"]
```

Това е малък пример без build стъпка. Ако проектът използва TypeScript, native зависимости или dev зависимости за компилиране, добави подходящ build етап и копирай резултата в runtime image. За възпроизводим release фиксирай и base image по проверен digest.

`.dockerignore`:

```text
.git
node_modules
.env
.env.*
*.sqlite*
*.db
```

`.gitignore` трябва да изключва поне `node_modules/`, `.env`, `.env.*`, SQLite файлове и backup-и. Не поставяй пароли, ключове или реални данни в image или Git.

### Локална проверка

От новото хранилище, с работещ Docker:

```sh
docker build -t foo:local .
docker run -d --name foo-local -p 127.0.0.1:18080:8080 foo:local
curl -fsS http://127.0.0.1:18080/health
curl -fsS http://127.0.0.1:18080/
docker logs foo-local
docker rm -f foo-local
```

Очаквай `healthy` и `hello from foo`. Портът в този тест е достъпен само локално. Ако името или портът вече са заети, избери други. Преди release изпълни и тестовете на реалния проект. Този тест не изисква GCP, `app-edge` или `gcplogs`.

## 3. Compose за VM

В новото repo `compose.yaml` може да изглежда така:

```yaml
services:
  foo:
    image: ${APP_IMAGE:?Set APP_IMAGE to the exact image digest}
    restart: unless-stopped
    networks: [app_edge]

networks:
  app_edge:
    external: true
    name: app-edge
```

`compose.gcp-logging.yaml`:

```yaml
services:
  foo:
    logging:
      driver: gcplogs
```

Двата файла трябва да са в новото repo и да се доставят заедно на VM. `APP_IMAGE` трябва да е пълен image адрес **с `@sha256:...`**, записан за избрания release. Не добавяй source bind mount над `/app`: той би скрил кода от image-а. Не добавяй `ports:`. За VM се ползват и двата Compose файла; локално не включвай GCP overlay. Настройките, които не са тайни, могат да са в Compose; тайните се доставят отделно от Git и image-а.

## 4. Публикуване и първо внедряване

Тези стъпки са план за изпълнение при създаване на реалното приложение; Artifact Registry и deploy автоматизацията още не са налични.

1. **На машината за build:** изпълни тестовете, изгради Docker image за архитектурата на VM и го публикувай в частен Artifact Registry repository. Запиши Git commit, image адрес и получения digest. [Artifact Registry: push и pull](https://docs.cloud.google.com/artifact-registry/docs/docker/pushing-and-pulling).
2. **В GCP:** създай repository и дай на VM service account-а `Artifact Registry Reader` за него. Отделната build самоличност има нужда от право за публикуване. Настрой Docker credential helper за потребителя, който изпълнява Docker командите на VM; при `sudo docker` провери конфигурацията за root. Тествай pull без JSON service account ключ. Ролята `Logs Writer` и scope-ът на настоящата VM вече са потвърдени за Cloud Logging.
3. **На VM:** провери `findmnt --mountpoint /srv/cloud-app-data` и `sudo docker network inspect app-edge`. Постави прегледаните Compose файлове в отделна папка на приложението, например `/srv/foo`; не ги смесвай с инфраструктурния проект. Потвърди точния image digest, текущите услуги и свободните ресурси.
4. **В папката на приложението на VM:** задай примерния адрес в променлива `APP_IMAGE` с действителен digest. При `sudo` предай променливата изрично. Първо валидирай и изтегли image-а; едва след успешно изтегляне стартирай услугата:

   ```sh
   APP_IMAGE='REGION-docker.pkg.dev/PROJECT/REPOSITORY/foo@sha256:DIGEST'
   sudo env APP_IMAGE="$APP_IMAGE" docker compose -f compose.yaml -f compose.gcp-logging.yaml config --quiet
   sudo env APP_IMAGE="$APP_IMAGE" docker compose -f compose.yaml -f compose.gcp-logging.yaml pull foo
   sudo env APP_IMAGE="$APP_IMAGE" docker compose -f compose.yaml -f compose.gcp-logging.yaml up -d --no-deps foo
   sudo env APP_IMAGE="$APP_IMAGE" docker compose -f compose.yaml -f compose.gcp-logging.yaml ps
   ```

   Това са примерни команди след замяна на всички условни стойности. За проверка отвътре използвай `sudo docker exec ИМЕ_НА_КОНТЕЙНЕРА node -e "fetch('http://127.0.0.1:8080/health').then(async r => { console.log(r.status, await r.text()); if (!r.ok) process.exitCode = 1 }).catch(() => process.exitCode = 1)"`. Името се вижда с `sudo docker ps`. Провери и логовете в Logs Explorer.
5. **Маршрут:** ако е нов, добави го в инфраструктурния `Caddyfile.apps`, като запазиш съществуващите маршрути:

   ```caddyfile
   @foo path /foo /foo/*
   handle @foo {
       uri strip_prefix /foo
       reverse_proxy foo:8080
   }
   ```

   Провери Caddy конфигурацията, достави променените файлове на VM и приложи от `/srv/cloud-vm-docker-starter` със `sudo bash ./start-gateway.sh`. Скриптът пресъздава Caddy, така че има кратко прекъсване; той не доставя файлове. При замяна на `gaz` с приложение, което запазва името `gaz` и порт 8080, нов маршрут не е нужен и gateway не се пресъздава.
6. Провери публичните `/foo/health`, реален потребителски път, `/health`, `/gaz/health` и `/mas/health`, доколкото маршрутите съществуват. Добави отделна uptime проверка за приложението. Регистрирай точните версии и резултатите.

## 5. Следващи версии и rollback

При всяка версия: тестове → build извън VM → push → запис на digest → pull на VM → пресъздаване само на съответната услуга с двата Compose файла → health и функционална проверка. Запази текущия и предишния image digest **и съответната Compose конфигурация**; не презаписвай данните на приложението. След неуспешен release върни предишния digest и съвместимата конфигурация, пресъздай само тази услуга и провери health и потребителския път. Един контейнер означава кратко прекъсване при смяната.

Бъдещият deploy скрипт трябва да автоматизира тези стъпки, включително заключване срещу едновременни deploy-и, валидиране на услугата и digest-а, изтегляне преди спирането, ограничено изчакване за readiness и проверен rollback. Нужно е да се тества и сценарий с неуспешно изтегляне или health проверка. Засега такъв скрипт и CI pipeline **няма**; първо трябва да бъдат изградени и проверени с реалния проект.

## 6. Данни и SQLite

Ако приложението има постоянни данни, монтирай отделна директория на `/srv/cloud-app-data`, провери собствеността и правата за потребителя в контейнера и не съхранявай базата само в слоя на image-а. SQLite е библиотека и файл, не отделен сървър. Преди реални данни са нужни автоматизиран съгласуван backup извън VM, проверен restore и аларма за пропуснат backup; виж [SQLite и backups](sqlite-and-backups.md). Преди schema миграция провери съвместимостта със старата версия и направи backup: връщането на image само по себе си не връща схемата или данните.

## 7. Какво остава да решим за конкретния проект

- Име на repo, услуга и публичен маршрут; дали заменя `gaz`.
- Поведение на приложението, health проверка, зависимости, поддържана Node версия и тестове.
- Нужни ли са SQLite, файлове, тайни, миграции и как ще се възстановяват.
- Кой изгражда image-а и как ще се управляват достъпът и разходите за registry и CI.
- Кога и как се стартира deploy; първото изпълнение и rollback трябва да се проверят преди автоматично внедряване.

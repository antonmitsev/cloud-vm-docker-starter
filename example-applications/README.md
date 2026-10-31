# Две Node.js приложения за проба

Тук има **два независими примера**: `gaz` слуша на порт 8080 и връща `hello from gaz`; `mas` слуша на 8081 и връща `hello from mas`. Всеки е в отделен контейнер. `gateway_demo` е локален Caddy, който показва маршрутизирането по `/gaz` и `/mas`. Примерите се стартират отделно от основния `start.sh`.

## Пусни локалната проба

От корена на хранилището:

```sh
docker network inspect app-edge >/dev/null 2>&1 || docker network create app-edge
cd example-applications
docker compose --profile demo up -d
curl -fsS http://127.0.0.1:8088/gaz
curl -fsS http://127.0.0.1:8088/mas
curl -fsS http://127.0.0.1:8088/gaz/health
curl -fsS http://127.0.0.1:8088/mas/health
```

Очакваните отговори са `hello from gaz`, `hello from mas`, `healthy`, `healthy`. За Docker команди добави `sudo`, ако локалният ти потребител няма достъп до Docker daemon. Демонстрационният Caddy е достъпен **само през `127.0.0.1:8088`**. Node услугите нямат `ports:` и не са публикувани на host-а.

## Смени кода сам

Отвори [`gaz/server.mjs`](gaz/server.mjs), смени текста `hello from gaz` с твой текст и запази файла. После от папката `example-applications`:

```sh
docker compose restart gaz
curl -fsS http://127.0.0.1:8088/gaz
```

Новият текст трябва да се появи. `mas` не се рестартира. Можеш да замениш **целия** `server.mjs` със свой HTTP сървър; остави `gaz` да слуша на `0.0.0.0:8080` (съответно `mas` на `0.0.0.0:8081`) и запази `/health`, ако ще го наблюдаваш. Редактирай файла в папката на проекта, а не вътре в контейнера. Кодът е bind mount, затова **промяна само на `.mjs` файл** се зарежда след рестарт на този контейнер. Ако промениш Compose настройка или env var, изпълни `docker compose up -d --force-recreate gaz` вместо `restart`; [Docker Compose не прилага нови env стойности с `restart`](https://docs.docker.com/reference/cli/docker/compose/restart/). Ако добавиш npm зависимости, изгради версиониран image с тях и го внедри отделно.

За ново приложение копирай една от папките под ново име, смени неговия вътрешен порт и отговор, добави услуга в [`compose.yaml`](compose.yaml) и маршрут в [`Caddyfile.demo`](Caddyfile.demo). Провери новия път с `curl`. Това са две кратки регистрации, защото Caddy трябва да знае кой публичен път към кой контейнер води.

## Как стига до реалния Caddy

На една VM е уместно Caddy да говори с Node контейнерите по **HTTP през общата Docker bridge мрежа**. Външният клиент продължава да използва HTTPS към Cloudflare/Caddy. За реално внедряване стартирай само `gaz` и `mas` от този Compose проект, без профила `demo`, и добави мрежата и маршрутите към **основните** `compose.yaml` и `Caddyfile` по [плана за Node приложенията](../docs/node-apps-bg.md). Тогава Caddy използва `gaz:8080` и `mas:8081`, а не `localhost`, защото `localhost` вътре в Caddy е самият Caddy контейнер. [Docker Compose networking](https://docs.docker.com/compose/how-tos/networking/).

В инфраструктурния проект има готови `compose.apps.yaml` и `Caddyfile.apps`. След като Node контейнерите работят и мрежата `app-edge` съществува, от папката на инфраструктурния проект приложи:

```sh
sudo docker compose -f compose.yaml -f compose.apps.yaml config --quiet
sudo docker compose -f compose.yaml -f compose.apps.yaml up -d gateway
```

Провери публичните `/health`, `/gaz`, `/mas` и двата application `/health` пътя. При следващи операции с gateway използвай **същите два `-f` аргумента**. Основният `start.sh` стартира само базовия `compose.yaml`, така че негово повторно изпълнение ще върне базовия Caddy; след това приложи overlay командата отново. Архивирай или доставяй собствените Node промени отделно, преди да обновяваш файловете на инфраструктурния проект.

Не публикувай 8080/8081 в GCP firewall и не добавяй `ports:` към Node услугите. При пренасяне на приложенията на **друга VM** преразгледай вътрешната връзка, мрежовите правила и TLS. За истинско приложение добави собствени health проверки, persistence/backup и контролирани image версии.

Спри локалната проба с `docker compose --profile demo down` от тази папка. Командата не изтрива общата `app-edge` мрежа, която може да се използва и от други контейнери.

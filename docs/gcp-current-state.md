# Анонимизиран отчет за изградената Google Cloud среда

**Последно потвърдено в работната сесия:** 25 октомври 2026 г.

**Проект:** идентификаторът е премахнат от публичното хранилище

**Подход:** ръчна настройка през Google Cloud Console и Cloud Shell; Terraform конфигурацията в `infra/` не е прилагана.

Това е запис на направеното и на резултатите, които видяхме в конзолата и терминала. Имената на ресурси, домейнът, адресите, UUID, service account и идентификаторите на обекти са умишлено премахнати или заменени с условни стойности. Не е автоматична проверка на текущото състояние в Google Cloud. Преди промяна или възстановяване вземи истинските стойности от конзолата или от частен операторски запис.

## Ресурси и настройки

| Област | Реално настроено | Къде се намира в конзолата |
| --- | --- | --- |
| Проект и разходи | Билинг акаунтът е свързан с проекта. Месечен бюджет **$26.50** за билинг акаунта, известия при 50%, 90%, 100% и 150%. Бюджетът изпраща известия, но не спира автоматично таксуването. | **Billing → Budgets & caps** |
| Местоположение | Регион `europe-west1` (Белгия), зона `europe-west1-b`. | **Compute Engine → VM instances** |
| Мрежа | Собствена VPC и subnet с частен IPv4 диапазон. Имената и диапазонът са премахнати. | **VPC network → VPC networks** |
| Firewall | Входящ TCP 80/443 е разрешен само от публикуваните IPv4 диапазони на Cloudflare; старото правило за `0.0.0.0/0` е изключено. TCP 22 остава разрешен само през IAP. Правилата действат чрез tag на VM. | **VPC network → Firewall** |
| Публичен адрес | Резервиран статичен IPv4, прикачен към VM. Адресът и името му са премахнати. | **VPC network → IP addresses** |
| VM | Ubuntu 24.04, `e2-small` (0.5 vCPU, 2 GiB RAM), зона `europe-west1-b`. Достъп чрез IAP и OS Login. Името и вътрешният IP са премахнати. | **Compute Engine → VM instances** |
| Boot disk | 20 GiB Balanced Persistent Disk. В конзолата беше показан дневен snapshot график с 14 дни съхранение. | **Compute Engine → Disks** |
| Data disk | 20 GiB Balanced Persistent Disk, прикачен към VM с правило **Keep disk** при изтриване на VM. Форматиран като ext4 и монтиран по UUID на `/srv/cloud-app-data`; уникалният UUID не е публикуван. Дневни snapshots със 7 дни съхранение. | **Compute Engine → Disks** |
| VM identity | Специален service account за VM. На bucket ниво е дадена роля **Storage Object Creator**. На VM са избрани пълни Cloud API access scopes; реалният достъп зависи и от IAM ролите. | **IAM & Admin → Service Accounts** и **Cloud Storage → Buckets → Permissions** |
| Backup bucket | Частен bucket в `europe-west1`, Standard, uniform bucket-level access и public access prevention. Soft delete: 7 дни. Името е премахнато. | **Cloud Storage → Buckets** |
| DNS и HTTPS | Авторитетните nameserver-и на основния домейн остават при досегашния DNS доставчик. API поддомейнът сочи с CNAME към проксиран hostname в отделна Cloudflare зона; Cloudflare for SaaS custom hostname и сертификатът са Active. Проксираният hostname сочи към статичния IPv4 адрес, а Caddy има публичен HTTPS сертификат за API поддомейна. Домейните и адресът са премахнати. | DNS управлението на двата домейна; Cloudflare for SaaS; VM/Caddy |
| Наблюдение | HTTPS uptime check за `/health`, очаква `200` и съдържание `healthy`; имейл известие за неуспех беше получено по време на настройката. | **Monitoring → Uptime checks** и **Monitoring → Alerting** |

При избора на региона калкулаторът показваше приблизително **$15.45 на месец** за разглежданата конфигурация на VM с boot disk в Белгия. Това не е реална фактура и не включва непременно всички отделно таксувани ресурси като data disk, публичен IPv4, snapshots, Cloud Storage и трафик.

След промяната на firewall-а външна проверка на `/health` през Cloudflare върна `200 healthy` с `server: cloudflare` и `cf-ray`. Нови директни връзки към публичния IPv4 адрес на TCP 80 и 443 изтекоха по време. За новото правило използвахме [официалните IPv4 диапазони на Cloudflare](https://www.cloudflare.com/ips/); при тяхна промяна списъкът в GCP трябва да се обнови. IP филтърът допуска всички изходни адреси на Cloudflare, затова сам по себе си не удостоверява кой Cloudflare акаунт е изпратил заявка.

Повторимите стъпки за отделния евтин домейн, custom hostname, DNS cutover и firewall са в [ръководството за един поддомейн през Cloudflare Free](cloudflare-single-subdomain-bg.md). Това е проверка на публичния трафик, а не пряк прочит на GCP firewall API след промяната.

HTTPS има два независими сертификатни слоя: Cloudflare управлява edge сертификатите за custom hostname, а Caddy управлява origin сертификата за същия API домейн. Успешният `/health` отговор не е проверка на бъдещото ACME подновяване на Caddy; наблюдавай срока на origin сертификата и логовете при подновяване. Подробностите са в [раздела за сертификати](cloudflare-single-subdomain-bg.md#сертификати-и-подновяване).

## Какво направихме на VM

1. Влязохме през Cloud Shell с `gcloud compute ssh` и IAP. Cloud Shell е отделна временна работна среда; командите за Docker и диска се изпълняват след SSH вход в VM.
2. Разпознахме отделния празен диск като `/dev/sdb`, форматирахме го **веднъж** и го монтирахме по UUID. `findmnt` показа `/dev/sdb` като ext4 на `/srv/cloud-app-data`; `df -h` показа приблизително 20 GiB свободно място. Монтирането беше проверено и след рестарт на VM.
3. Инсталирахме Docker Engine 29.9.2 и Docker Compose 5.6.1. Тези версии са запис от настройката, а не обещание за бъдещата им версия.
4. Поставихме проекта в `/srv/cloud-vm-docker-starter`. Реалният `.env` е извън Git, с `APP_DOMAIN` за истинския домейн; стойностите му не трябва да се копират в хранилището.
5. Стартирахме Compose услугата `gateway` с Caddy. Началният адрес връща `Cloud VM ready`. Специалният `/health` връща `200 healthy`; конфигурацията задава `404` за непознатите пътища. Промяната беше приложена на VM с пресъздаване на `gateway` контейнера.
6. Настроихме snapshot график за data disk и проверихме ръчно отделен път за SQLite резервно копие към Cloud Storage.

Проверки от VM или друга машина (замени `YOUR_DOMAIN` с истинския домейн):

```sh
curl -i https://YOUR_DOMAIN/health
curl -i https://YOUR_DOMAIN/
```

На VM проверявай монтирания диск преди работа с Compose:

```sh
findmnt --mountpoint /srv/cloud-app-data
cd /srv/cloud-vm-docker-starter
sudo docker compose ps
```

За достъп от Cloud Shell:

```sh
gcloud compute ssh VM_NAME \
  --project=PROJECT_ID \
  --zone=ZONE \
  --tunnel-through-iap
```

SSH командата може да поиска пасфразата на локалния ключ в Cloud Shell. Не записвай пасфрази или частни ключове в този документ.

## Проверка на резервно копие и възстановяване

- VM service account успя да създаде пробен обект в backup bucket чрез Cloud Storage JSON API `objects.insert`.
- `gcloud storage cp` от VM върна **403** за `storage.objects.get` при достъп до обект, защото ролята **Storage Object Creator** не дава право за четене. При бъдеща автоматизация не приемай, че тази CLI команда работи с текущите права; използвай проверения write-only API подход или прегледай IAM модела.
- Качихме пробна SQLite база в bucket. В отделна Cloud Shell с операторски достъп я изтеглихме и отворихме: `PRAGMA integrity_check` върна `ok`, а пробният запис беше `backup-ok`.
- Това е **ръчен тест с пробна база**, не автоматизирано архивиране на истинско приложение. Snapshot графикът защитава диска по отделен механизъм; не сме потвърждавали всеки автоматичен snapshot или възстановяване от snapshot.

## Какво още не е готово

- Няма внедрено приложение или реална SQLite база. `/health` в момента проверява **Caddy**, а не работата на бъдещото приложение. Когато добавим приложение, запазваме публичния адрес `/health`, но го свързваме с неговата проверка.
- Няма периодична задача за SQLite backup, проверка за възрастта на последния backup или аларма при неуспешен backup.
- Не сме документирали като завършени метрики и аларми за памет/диск или потвърдено възстановяване от disk snapshot.
- Terraform файловете са само подготвена алтернатива. **Не изпълнявай `terraform apply` срещу този проект без план за внасяне на ръчно създадените ресурси в Terraform state**; иначе планът може да предлага дублиращи ресурси или конфликти.

## Handoff: първо внедряване на приложението

### Решение за доставка

- Git остава мястото за сорс кода и Compose/Caddy конфигурацията. VM може да изтегля конфигурационен комит, но **не билдва приложението**.
- Приложението се пакетира като Docker image извън VM и се публикува в частен Artifact Registry. VM изтегля готовия image и го стартира чрез Compose. Така deployment използва записана версия на image и не товари малката VM с компилация.
- Първото внедряване е полуавтоматично: човек стартира build и публикуване; после влиза през IAP, изтегля избрания image, стартира Compose и проверява `/health`.
- След като този път мине успешно, build/publish може да се върже към GitHub Actions или Cloud Build. Самото внедряване в production остава с ръчно потвърждение, докато не натрупаме опит с backup, health check и rollback.
- Доставчикът на CI още не е избран и нито Artifact Registry, нито build trigger са създадени. Това решение зависи от реалното приложение и неговия Dockerfile.

### Преди първия production deployment

1. Да има работещо приложение, Dockerfile, Compose service и истинска проверка на приложението зад публичния `/health`.
2. Да се създаде частен Artifact Registry repository.
3. На VM service account да се даде `Artifact Registry Reader` само за този repository; да се потвърди, че VM access scope позволява четене от registry.
4. Да се изгради image с таг по Git commit и да се запише digest-ът му. Да не се ползва подвижен `latest` таг за production release.
5. Преди schema промяна да има проверен off-VM backup. След deployment да се провери `/health`, нормалният потребителски път, логовете и рестартът на контейнера.
6. Да се запише предишният image digest и работещата Compose/Caddy конфигурация, за да може rollback-ът да върне известна работеща версия.

### Rollback

При проблем избери предишния записан image digest и конфигурационен Git commit, приложи ги с Compose и провери `/health`. Ако приложението е променило схемата на базата, връщането на image само по себе си може да не е достатъчно; миграцията трябва да поддържа съвместим rollback или да има отделен restore план.

За следващото внедряване виж [ръчната VM процедура](google-cloud-vm.md), [операциите](operations.md), [SQLite backup и restore](sqlite-and-backups.md) и [плана за бъдещото приложение](gcp-deployment-plan.md).

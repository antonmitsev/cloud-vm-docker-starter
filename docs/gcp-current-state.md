# Реално изградената Google Cloud среда

**Последно потвърдено в работната сесия:** 25 октомври 2026 г.

**Проект:** `example-project-id`

**Подход:** ръчна настройка през Google Cloud Console и Cloud Shell; Terraform конфигурацията в `infra/` не е прилагана.

Това е запис на направеното и на резултатите, които видяхме в конзолата и терминала. Не е автоматична проверка на текущото състояние в Google Cloud. Преди промяна или възстановяване сравни посочените стойности с реалните ресурси.

## Ресурси и настройки

| Област | Реално настроено | Къде се намира в конзолата |
| --- | --- | --- |
| Проект и разходи | Билинг акаунтът е свързан с проекта. Месечен бюджет **$26.50** за билинг акаунта, известия при 50%, 90%, 100% и 150%. Бюджетът изпраща известия, но не спира автоматично таксуването. | **Billing → Budgets & caps** |
| Местоположение | Регион `europe-west1` (Белгия), зона `europe-west1-b`. | **Compute Engine → VM instances** |
| Мрежа | VPC `cloud-app-vpc`, subnet `cloud-app-subnet`, диапазон `10.42.0.0/24`. | **VPC network → VPC networks** |
| Firewall | `cloud-app-web`: входящ TCP 80/443 от `0.0.0.0/0`; `cloud-app-iap-ssh`: входящ TCP 22 от `35.235.240.0/20`. И двете правила са за мрежов tag `cloud-app-server` във `cloud-app-vpc`; tag е приложен към VM. | **VPC network → Firewall** |
| Публичен адрес | Резервиран статичен IPv4 `cloud-api-ip` = `203.0.113.10`, прикачен към VM. | **VPC network → IP addresses** |
| VM | `cloud-app-vm`, Ubuntu 24.04, `e2-small` (0.5 vCPU, 2 GiB RAM), зона `europe-west1-b`. Основен вътрешен адрес `10.0.0.2`. Достъп чрез IAP и OS Login. | **Compute Engine → VM instances** |
| Boot disk | 20 GiB Balanced Persistent Disk `cloud-app-vm`. В конзолата беше показан график `default-schedule-1` за дневни snapshots с 14 дни съхранение. | **Compute Engine → Disks** |
| Data disk | 20 GiB Balanced Persistent Disk `cloud-app-data`, прикачен към VM с правило **Keep disk** при изтриване на VM. Форматиран като ext4, UUID `00000000-0000-0000-0000-000000000000`, монтиран на `/srv/cloud-app-data`. График `cloud-app-data-daily` за дневни snapshots със 7 дни съхранение. | **Compute Engine → Disks** |
| VM identity | Service account `cloud-app-vm@example-project-id.iam.gserviceaccount.com`. На bucket ниво е дадена роля **Storage Object Creator**. На VM са избрани пълни Cloud API access scopes; реалният достъп зависи и от IAM ролите. | **IAM & Admin → Service Accounts** и **Cloud Storage → Buckets → Permissions** |
| Backup bucket | Частен bucket `example-project-id-cloud-app-backups` в `europe-west1`, Standard, uniform bucket-level access и public access prevention. Soft delete: 7 дни. | **Cloud Storage → Buckets** |
| DNS и HTTPS | `api.example.com` сочи към `203.0.113.10`. DNS A записът е настроен извън GCP. Caddy издаде публичен HTTPS сертификат автоматично. | DNS управлението на домейна; VM/Caddy за HTTPS |
| Наблюдение | HTTPS uptime check `cloud-app-https` за `api.example.com/health`, очаква `200` и съдържание `healthy`; имейл известие за неуспех беше получено по време на настройката. | **Monitoring → Uptime checks** и **Monitoring → Alerting** |

При избора на региона калкулаторът показваше приблизително **$15.45 на месец** за разглежданата конфигурация на VM с boot disk в Белгия. Това не е реална фактура и не включва непременно всички отделно таксувани ресурси като data disk, публичен IPv4, snapshots, Cloud Storage и трафик.

## Какво направихме на VM

1. Влязохме през Cloud Shell с `gcloud compute ssh` и IAP. Cloud Shell е отделна временна работна среда; командите за Docker и диска се изпълняват след SSH вход в `cloud-app-vm`.
2. Разпознахме отделния празен диск като `/dev/sdb`, форматирахме го **веднъж** и го монтирахме по UUID. `findmnt` показа `/dev/sdb` като ext4 на `/srv/cloud-app-data`; `df -h` показа приблизително 20 GiB свободно място. Монтирането беше проверено и след рестарт на VM.
3. Инсталирахме Docker Engine 29.9.2 и Docker Compose 5.6.1. Тези версии са запис от настройката, а не обещание за бъдещата им версия.
4. Поставихме проекта в `/srv/cloud-vm-docker-starter`. Реалният `.env` е извън Git, с `APP_DOMAIN=api.example.com`; стойности или съдържанието му не трябва да се копират в хранилището.
5. Стартирахме Compose услугата `gateway` с Caddy. Началният адрес връща `Cloud VM ready`. Специалният `/health` връща `200 healthy`; конфигурацията задава `404` за непознатите пътища. Промяната за `/health` е в Git комит `07e7c8c` и беше приложена на VM с пресъздаване на `gateway` контейнера.
6. Настроихме snapshot график за data disk и проверихме ръчно отделен път за SQLite резервно копие към Cloud Storage.

Проверки от VM или друга машина:

```sh
curl -i https://api.example.com/health
curl -i https://api.example.com/
```

На VM проверявай монтирания диск преди работа с Compose:

```sh
findmnt --mountpoint /srv/cloud-app-data
cd /srv/cloud-vm-docker-starter
sudo docker compose ps
```

За достъп от Cloud Shell:

```sh
gcloud compute ssh cloud-app-vm \
  --project=example-project-id \
  --zone=europe-west1-b \
  --tunnel-through-iap
```

SSH командата може да поиска пасфразата на локалния ключ в Cloud Shell. Не записвай пасфрази или частни ключове в този документ.

## Проверка на резервно копие и възстановяване

- VM service account успя да създаде обект в backup bucket чрез Cloud Storage JSON API `objects.insert`. Пробният текстов обект беше `probe-20261024T215930Z.txt`.
- `gcloud storage cp` от VM върна **403** за `storage.objects.get` при достъп до обект, защото ролята **Storage Object Creator** не дава право за четене. При бъдеща автоматизация не приемай, че тази CLI команда работи с текущите права; използвай проверения write-only API подход или прегледай IAM модела.
- Качихме пробна SQLite база `sqlite-probe-20261024T220159Z.sqlite` в bucket. В отделна Cloud Shell с операторски достъп я изтеглихме и отворихме: `PRAGMA integrity_check` върна `ok`, а пробният запис беше `backup-ok`.
- Това е **ръчен тест с пробна база**, не автоматизирано архивиране на истинско приложение. Snapshot графикът защитава диска по отделен механизъм; не сме потвърждавали всеки автоматичен snapshot или възстановяване от snapshot.

## Какво още не е готово

- Няма внедрено приложение или реална SQLite база. `/health` в момента проверява **Caddy**, а не работата на бъдещото приложение. Когато добавим приложение, запазваме публичния адрес `/health`, но го свързваме с неговата проверка.
- Няма периодична задача за SQLite backup, проверка за възрастта на последния backup или аларма при неуспешен backup.
- Не сме документирали като завършени метрики и аларми за памет/диск или потвърдено възстановяване от disk snapshot.
- Terraform файловете са само подготвена алтернатива. **Не изпълнявай `terraform apply` срещу този проект без план за внасяне на ръчно създадените ресурси в Terraform state**; иначе планът може да предлага дублиращи ресурси или конфликти.

За следващото внедряване виж [ръчната VM процедура](google-cloud-vm.md), [операциите](operations.md), [SQLite backup и restore](sqlite-and-backups.md) и [плана за бъдещото приложение](gcp-deployment-plan.md).

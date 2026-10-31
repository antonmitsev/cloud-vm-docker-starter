# От нула до работеща облачна основа: чеклист

Това е **процедура за нова среда**, а не историята на вече създадената. Следвай реда. Всяка отметка казва **къде**, **какво** и **как проверяваш**. Примерите `PROJECT_ID`, `VM_NAME`, `api.example.com`, `origin.example.net` и `203.0.113.10` не са реални стойности. Запиши истинските имена, адреси, UUID и достъпи само в свой локален операторски файл, извън Git.

Накрая ще работи една Ubuntu VM с отделен диск, Docker Compose и Caddy, публичен HTTPS `/health` през Cloudflare, дневни disk snapshots, ръчно проверен off-VM backup път и имейл аларма за uptime. **Тук още няма приложение и база с реални данни.** Автоматичният SQLite backup и алармата за срока на Caddy origin сертификата са отделни задачи преди продукционни данни.

## 0. Подготви достъпа, преди Google Cloud проекта

- [ ] **В браузъра:** влез или създай [Google акаунт](https://accounts.google.com/) с включена двуфакторна защита. Отвори [Google Cloud Console](https://console.cloud.google.com/) и приеми началните условия, ако се покажат. Провери, че можеш да отвориш [Cloud Shell](https://shell.cloud.google.com/) от иконата `>_` горе вдясно или от директния линк. Cloud Shell е отделен терминал, а не бъдещата VM.
- [ ] **При регистратора на основния домейн:** осигури домейн, чийто DNS можеш да редактираш, например `example.com`. Провери, че можеш да добавяш `A`, `CNAME` и `TXT` записи. Избери свободен поддомейн, например `api.example.com`. Запиши при кой доставчик са авторитетните nameserver-и.
- [ ] **В [GitHub проекта](https://github.com/antonmitsev/cloud-vm-docker-starter):** отвори `README.md`, `compose.yaml` и `Caddyfile`; потвърди, че ще стартираш този публичен код. На VM не е нужен Git checkout.
- [ ] **В [Cloudflare](https://dash.cloudflare.com/):** направи акаунт, до който ще имаш достъп и след настройката. Вторият домейн за Cloudflare ще добавиш на стъпка 12. Финалният резултат на този чеклист включва Cloudflare.

## 1. Създай проект и свържи плащането

- [ ] **Google Cloud Console → [Select a project → New Project](https://console.cloud.google.com/projectcreate):** дай име, запиши `PROJECT_ID` и избери проекта от горния селектор. За нова среда не използвай случайно стар проект.
- [ ] **Console → [Billing](https://console.cloud.google.com/billing):** създай billing account, добави метод за плащане и свържи новия проект. Провери в проекта, че Billing е **Enabled**. Ако вече имаш billing account, свържи него. [Официални стъпки за billing account](https://docs.cloud.google.com/billing/docs/how-to/create-billing-account) и [свързване на проект](https://docs.cloud.google.com/billing/docs/how-to/modify-project).
- [ ] **Console → Billing → [Budgets & alerts](https://console.cloud.google.com/billing/budgets):** създай месечен бюджет за този проект и имейл прагове, например 50%, 90% и 100%. Избери сума според [калкулатора](https://cloud.google.com/products/calculator): VM, boot и data disk, външен IPv4, snapshots, bucket, Monitoring и трафик. Провери, че бюджетът се вижда в списъка. **Бюджетното известие не е автоматичен стоп на разходите.** [Документация](https://docs.cloud.google.com/billing/docs/how-to/budgets).

## 2. Избери регион, идентичности и мрежа

- [ ] **В локалния си операторски файл:** избери `REGION`, `ZONE`, `VM_NAME`, име на VPC/subnet и свободен частен CIDR, например `10.20.0.0/24`. Дискът и VM трябва да са в една зона. Провери цената за точния регион.
- [ ] **Console → [VPC network → VPC networks](https://console.cloud.google.com/networking/networks/list):** създай VPC с **Custom subnet creation**; добави един subnet в избрания регион с избрания CIDR. Провери, че subnet-ът се показва под новата VPC.
- [ ] **Console → [IAM & Admin → Service Accounts](https://console.cloud.google.com/iam-admin/serviceaccounts):** създай отделен service account за VM, без ключов JSON файл. По-късно ще му дадеш право да **създава обекти само в backup bucket**.
- [ ] **Console → [IAM & Admin → IAM](https://console.cloud.google.com/iam-admin/iam):** за оператора осигури права за IAP tunnel и OS Login/администриране според [официалното IAP ръководство](https://docs.cloud.google.com/iap/docs/using-tcp-forwarding). Ако създаването на VM с избрания service account поиска `Service Account User`, дай това право на оператора. Провери правата с реален IAP SSH вход на стъпка 5.
- [ ] **Console → [VPC network → Firewall](https://console.cloud.google.com/networking/firewalls/list):** създай ingress правило за **TCP 22** от `35.235.240.0/20`, ограничено с отделен target network tag, например `app-vm`. Това е [диапазонът на IAP](https://docs.cloud.google.com/compute/docs/connect/ssh-best-practices/network-access). Създай второ, временно ingress правило за **TCP 80,443** от `0.0.0.0/0` към същия tag за първото издаване на Caddy сертификат. Не отваряй портове за приложение или база. Провери посоката, VPC, source range, портовете и tag-а на двете правила.

## 3. Резервирай адрес и създай VM

- [ ] **Console → [VPC network → IP addresses](https://console.cloud.google.com/networking/addresses/list):** резервирай **regional static external IPv4** в избрания регион. Запиши адреса локално. [Документация](https://docs.cloud.google.com/compute/docs/ip-addresses/configure-static-external-ip-address).
- [ ] **Console → [Compute Engine → VM instances → Create instance](https://console.cloud.google.com/compute/instances):** избери `ZONE`, Ubuntu 24.04 LTS, размер според калкулатора (например `e2-small`) и boot disk. В **Networking** избери само собствената VPC/subnet, резервирания IPv4 и същия network tag. Не включвай автоматичните отметки за HTTP/HTTPS, защото вече има целево firewall правило. В **Security/Identity** избери новия service account и Cloud API access scope `Allow full access to all Cloud APIs`; конкретните права ще ограничиш с IAM върху bucket. В **Advanced options → Metadata** добави `enable-oslogin=TRUE`. Провери настройките, после създай VM. [Създаване на VM](https://docs.cloud.google.com/compute/docs/create-linux-vm-instance) и [OS Login](https://docs.cloud.google.com/compute/docs/oslogin/set-up-oslogin).
- [ ] **Console → VM instances:** провери `Running`, правилния външен IP, мрежа, зона, service account и network tag. Запиши тези стойности локално.

## 4. Добави отделен диск, който остава при смяна на VM

- [ ] **Console → [Compute Engine → Disks](https://console.cloud.google.com/compute/disks):** създай празен `pd-balanced` data disk в **същата зона**; 20 GiB е пример, размерът зависи от данните. Прикачи го към VM през **VM instances → VM_NAME → Edit → Storage → Add existing disk**. Задай **Keep disk** при изтриване на VM. Провери, че дисковете са два и data disk е `Keep disk`. [Добавяне на диск](https://docs.cloud.google.com/compute/docs/disks/add-persistent-disk) и [поведение при изтриване](https://docs.cloud.google.com/compute/docs/disks/modify-persistent-disk).

## 5. Влез през Cloud Shell и монтирай диска

- [ ] **Console → Cloud Shell:** изпълни командата с твоите локално записани стойности. След SSH prompt-а вече си **във VM**. При първо свързване `gcloud` може да създаде SSH ключ и да поиска passphrase; запази я в мениджър за пароли, не в Git.

  ```sh
  gcloud compute ssh VM_NAME --project=PROJECT_ID --zone=ZONE --tunnel-through-iap
  ```

- [ ] **На VM:** изпълни `lsblk -f` и `ls -l /dev/disk/by-id/google-*`. Съпостави новия **празен** диск с името му в Console. Само него форматирай като ext4 по [ръководството на Google](https://docs.cloud.google.com/compute/docs/disks/format-mount-disk-linux). Например, след като потвърдиш точния device path, изпълни `sudo mkfs.ext4 /dev/disk/by-id/google-DATA_DISK_NAME`. Форматирането изтрива данни; при възстановяване на стар диск пропусни тази операция.
- [ ] **На VM:** вземи UUID на новата ext4 файлова система с `sudo blkid`, създай `/srv/cloud-app-data`, добави в `/etc/fstab` ред като примера долу, после изпълни `sudo mount /srv/cloud-app-data`. Използвай **истинския UUID само във VM**. [Постоянни имена на дисковете](https://docs.cloud.google.com/compute/docs/disks/set-persistent-device-name-in-linux-vm).

  ```text
  UUID=<UUID_НА_DATA_DISK> /srv/cloud-app-data ext4 defaults 0 2
  ```

- [ ] **На VM:** `findmnt --mountpoint /srv/cloud-app-data` трябва да покаже отделния data disk и `ext4`; `df -h /srv/cloud-app-data` трябва да показва неговия размер. Ако не, спри тук.

## 6. Инсталирай Docker и Compose на VM

- [ ] **На VM:** инсталирай от [официалния Docker `apt` repository](https://docs.docker.com/engine/install/ubuntu/). За чиста Ubuntu 24.04 изпълни следните команди; ако Docker промени инструкциите, ползвай актуалните от линка.

  ```sh
  sudo apt update
  sudo apt install -y ca-certificates curl
  sudo install -m 0755 -d /etc/apt/keyrings
  sudo curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
  sudo chmod a+r /etc/apt/keyrings/docker.asc
  sudo tee /etc/apt/sources.list.d/docker.sources >/dev/null <<EOF
  Types: deb
  URIs: https://download.docker.com/linux/ubuntu
  Suites: $(. /etc/os-release && echo "${UBUNTU_CODENAME:-$VERSION_CODENAME}")
  Components: stable
  Architectures: $(dpkg --print-architecture)
  Signed-By: /etc/apt/keyrings/docker.asc
  EOF
  sudo apt update
  sudo apt install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
  ```

  Провери резултата:

  ```sh
  sudo docker version
  sudo docker compose version
  sudo systemctl is-enabled docker.service
  ```

  Първите две трябва да показват версии, последната — `enabled`. Ако Docker guide е променен, използвай актуалните му команди. Не добавяй оператора в `docker` групата само за удобство; `sudo docker` е достатъчно.

## 7. Дай на Caddy DNS име и пусни проекта с `start.sh`

- [ ] **При DNS доставчика на `example.com`:** създай временен `A` запис `api.example.com → <STATIC_IPV4>`. Провери с `dig +short api.example.com A`, че публичният отговор е резервираният адрес. Остави временното firewall правило за 80/443 активно до успешно издаване на Caddy сертификата.
- [ ] **На VM:** инсталирай `start.sh` извън папката, която самият скрипт обновява, после го изпълни. Замени примерния домейн с твоя. Скриптът изтегля GitHub архива без `.git`, пази съществуващия `.env`, създава го при първо пускане, проверява mount point-а и стартира Compose.

  ```sh
  curl -fsSL https://raw.githubusercontent.com/antonmitsev/cloud-vm-docker-starter/main/start.sh -o /tmp/cloud-vm-start.sh
  sudo install -m 0755 /tmp/cloud-vm-start.sh /usr/local/sbin/cloud-vm-start
  sudo APP_DOMAIN=api.example.com /usr/local/sbin/cloud-vm-start
  ```

  При следващо **съзнателно обновяване**: `sudo /usr/local/sbin/cloud-vm-start`. За фиксиран commit може да зададеш `SOURCE_REF=<40-символен-комит>`; `main` по подразбиране изтегля текущата версия. Скриптът не инсталира Google ресурси, Docker или DNS — те са стъпки 1–6.
- [ ] **На VM:** влез в `/srv/cloud-vm-docker-starter` и провери `sudo docker compose ps` и `sudo docker compose logs --tail=80 gateway`. Трябва да има работещ `gateway` и успешно издаване/зареждане на сертификат. При ACME грешка провери A записа и публичния достъп по 80/443.
- [ ] **От компютъра или Cloud Shell:** `curl -i https://api.example.com/health` трябва да върне **HTTP 200** и `healthy`, без `-k`. `curl -i https://api.example.com/` трябва да върне `Cloud VM ready`. Това е проверка на Caddy, още не на приложение.

## 8. Подсигури стартирането след рестарт

- [ ] **На VM:** инсталирай [примерния systemd mount guard](../systemd/docker.service.d/10-require-data-disk.conf.example) по [операционните стъпки](operations.md#start-docker-only-after-the-data-disk), като замениш примерния път с `/srv/cloud-app-data`. Той кара Docker да изчака data disk и да откаже старт, ако дискът не е монтиран. `restart: unless-stopped` в Compose възстановява вече стартирания Caddy контейнер при нормален boot.
- [ ] **При планиран рестарт на VM:** провери пак `findmnt --mountpoint /srv/cloud-app-data`, `systemctl is-active docker.service`, `sudo docker compose ps` и публичния `/health`. Guard-ът е готов едва след тази проверка.

## 9. Създай backup bucket и тествай възстановяване

- [ ] **Console → [Cloud Storage → Buckets](https://console.cloud.google.com/storage/browser):** създай частен bucket в избрания регион със Standard storage, **uniform bucket-level access**, **public access prevention** и подходящ soft delete период. Запиши името локално. Отвори **bucket → Permissions → Grant access**, добави VM service account с роля **Storage Object Creator** само за този bucket. Това е write-only право; не е нужно VM да чете копията. [Роли за Storage](https://docs.cloud.google.com/storage/docs/access-control/iam-roles).
- [ ] **На VM:** създай малка пробна SQLite база, направи съгласуван `.backup` и качи **нов обект** в bucket чрез Cloud Storage JSON API `objects.insert` с VM service account. Замени `YOUR_BACKUP_BUCKET` с истинското име **само във VM**. Командите използват Python SQLite, който е наличен на стандартната Ubuntu инсталация, и token от VM metadata service. Не показвай token-а и не включвай `set -x`.

  ```sh
  BUCKET=YOUR_BACKUP_BUCKET
  PROBE_DIR=$(mktemp -d)
  python3 - "$PROBE_DIR" <<'PY'
  import sqlite3, sys
  from pathlib import Path
  folder = Path(sys.argv[1])
  source = sqlite3.connect(folder / 'source.sqlite')
  source.execute('CREATE TABLE probe (value TEXT)')
  source.execute('INSERT INTO probe VALUES (?)', ('backup-ok',))
  source.commit()
  backup = sqlite3.connect(folder / 'probe.sqlite')
  source.backup(backup)
  print(backup.execute('PRAGMA integrity_check').fetchone()[0])
  print(backup.execute('SELECT value FROM probe').fetchone()[0])
  backup.close()
  source.close()
  PY
  OBJECT="probe-$(date -u +%Y%m%dT%H%M%SZ).sqlite"
  TOKEN=$(curl -fsS -H 'Metadata-Flavor: Google' http://metadata.google.internal/computeMetadata/v1/instance/service-accounts/default/token | python3 -c 'import json,sys; print(json.load(sys.stdin)["access_token"])')
  curl -fsS -X POST -H "Authorization: Bearer $TOKEN" -H 'Content-Type: application/octet-stream' --data-binary @"$PROBE_DIR/probe.sqlite" "https://storage.googleapis.com/upload/storage/v1/b/$BUCKET/o?uploadType=media&name=$OBJECT"
  unset TOKEN
  printf 'Uploaded gs://%s/%s\n' "$BUCKET" "$OBJECT"
  ```

  Първите два реда от Python трябва да са `ok` и `backup-ok`; upload трябва да върне JSON с името на обекта. Запиши `BUCKET` и `OBJECT` локално. При write-only ролята `gcloud storage cp` **от VM** може да поиска `storage.objects.get` и да върне `403`; горният API upload изисква само `storage.objects.create`. [API документация](https://docs.cloud.google.com/storage/docs/json_api/v1/objects/insert). Изтрий временната проба от VM след успешен restore.
- [ ] **В Cloud Shell с операторски права, извън VM:** изпълни с записаните стойности. Твоят операторски акаунт трябва да има право да чете обекта. Резултатът трябва да е `ok`, после `backup-ok`:

  ```sh
  BUCKET=YOUR_BACKUP_BUCKET
  OBJECT=probe-YYYYMMDDTHHMMSSZ.sqlite
  gcloud storage cp "gs://$BUCKET/$OBJECT" /tmp/probe-restored.sqlite
  python3 - <<'PY'
  import sqlite3
  db = sqlite3.connect('/tmp/probe-restored.sqlite')
  print(db.execute('PRAGMA integrity_check').fetchone()[0])
  print(db.execute('SELECT value FROM probe').fetchone()[0])
  db.close()
  PY
  ```

  Запиши локално датата и резултата. Без успешно сваляне и отваряне backup пътят не е проверен. Това доказва **ръчно** архивиране на пробни данни, не автоматичен backup на бъдещо приложение.

## 10. Включи дневни snapshots

- [ ] **Console → Compute Engine → Disks → data disk → Edit → Snapshot schedule:** създай дневен график и retention, например 7 дни; прикачи го към data disk. За boot disk избери отделен график, ако искаш бързо възстановяване на системата. Провери в двата диска кой schedule е приложен. [Официални стъпки](https://docs.cloud.google.com/compute/docs/disks/scheduled-snapshots).
- [ ] **След първия планиран час:** отвори [Compute Engine → Snapshots](https://console.cloud.google.com/compute/snapshots), намери реално създаден snapshot и провери източника и датата. Избери **Create disk** от него, дай ново име и зона на пробна VM; прикачи новия диск към пробната VM, монтирай го **само за четене** и провери, че файловете на Caddy са налични. Запиши резултата локално и изтрий пробния диск, когато приключиш. Не прикачай възстановения диск вместо работещия без отделен план. Snapshot на работещ SQLite файл не замества неговия съгласуван `.backup`. [Възстановяване от snapshot](https://docs.cloud.google.com/compute/docs/disks/restore-snapshot).

## 11. Настрой `/health` аларма

- [ ] **Console → Monitoring → Alerting → Manage notification channels:** добави имейл адрес и го потвърди.
- [ ] **Console → [Monitoring → Uptime checks](https://console.cloud.google.com/monitoring/uptime):** създай HTTPS проверка за `api.example.com`, path `/health`, очакван код `200` и текст `healthy`. Натисни **Test**. Включи alert policy за failed uptime check и избери потвърдения имейл канал, после **Create**. Провери, че проверката е зелена и policy е активна. Потвърди и че имейлът действително стига — например при контролирана кратка пауза в уговорен прозорец. Тази проверка вижда Caddy `/health`, не бъдещото приложение. [Официална процедура](https://docs.cloud.google.com/monitoring/uptime-checks).

## 12. Подготви Cloudflare, без да местиш основния домейн

- [ ] **При регистратора:** купи/използвай втори домейн, например `example.net`. Добави **само него** като зона в [Cloudflare](https://dash.cloudflare.com/), избери допустимия план и смени **само неговите** nameserver-и според Cloudflare. Изчакай зоната да е `Active`. `example.com` и пощата му остават при досегашния DNS доставчик. Провери актуалните [условия за Cloudflare for SaaS](https://developers.cloudflare.com/cloudflare-for-platforms/cloudflare-for-saas/plans/) и [активиране](https://developers.cloudflare.com/cloudflare-for-platforms/cloudflare-for-saas/start/enable/) преди плащане.
- [ ] **Cloudflare → DNS за `example.net`:** добави `origin.example.net` като **Proxied** `A` запис към статичния IPv4 на VM. В **Cloudflare for SaaS → Custom Hostnames → Fallback Origin** посочи `origin.example.net` и изчакай `Active`. [Официални стъпки](https://developers.cloudflare.com/cloudflare-for-platforms/cloudflare-for-saas/start/getting-started/).
- [ ] **Cloudflare → SSL/TLS:** за връзката към origin избери **Full (strict)**. Caddy вече трябва да има валиден сертификат за `api.example.com` от стъпка 7. [Режим Full (strict)](https://developers.cloudflare.com/ssl/origin-configuration/ssl-modes/full-strict/).
- [ ] **Cloudflare for SaaS → Custom Hostnames:** добави `api.example.com`. **При стария DNS доставчик на `example.com`** добави точно TXT записите, които Cloudflare показва за hostname ownership и certificate validation. Изчакай едновременно **Hostname: Active** и **Certificate: Active**. [Валидация](https://developers.cloudflare.com/cloudflare-for-platforms/cloudflare-for-saas/domain-support/hostname-validation/).

## 13. Превключи DNS и затвори директния IP

- [ ] **При стария DNS доставчик:** замени **само** `A` записа на `api.example.com` с `CNAME` към `origin.example.net`; не оставяй A и CNAME за едно име. Провери `dig +short CNAME api.example.com`, после `curl -i https://api.example.com/health`: очаквай `200 healthy` и заглавка `cf-ray`.
- [ ] **Console → VPC network → Firewall:** добави правило за TCP **80,443** от [актуалните Cloudflare IPv4 диапазони](https://www.cloudflare.com/ips/) към същия VM tag. След успешен публичен `/health` през Cloudflare **изключи** временното правило `0.0.0.0/0` за 80/443. Не променяй IAP правилото за 22. Провери нов `/health` отговор и пробвай директна връзка към IPv4 от външна мрежа — тя трябва да изтече по време. [Подробни проверки и връщане назад](cloudflare-single-subdomain-bg.md#проверка-и-връщане-назад).

## 14. Финална проверка и операторски запис

- [ ] **От външна машина:** `curl -i https://api.example.com/health` връща `200 healthy` и `cf-ray`. **На VM:** `findmnt --mountpoint /srv/cloud-app-data`, `sudo docker compose ps` и `systemctl is-active docker.service` са успешни.
- [ ] **Cloudflare:** custom hostname и edge certificate са `Active`; **на VM** провери отделния **Caddy origin** сертификат и ACME логовете по [операционната процедура](operations.md#check-caddys-origin-certificate-renewal). Публичният сертификат е на Cloudflare и не доказва подновяване на Caddy сертификата. Следи Caddy сертификата до действително успешно подновяване през Cloudflare.
- [ ] **Google Cloud:** виж успешен uptime check и активна имейл policy; провери реално получен тестов имейл. Виж качения пробен backup, успешното му отваряне в Cloud Shell и реален disk snapshot с пробно възстановяване. Прегледай разходите в Billing.
- [ ] **Само локално, извън Git:** запиши project ID, zone, VM, disk, mount UUID, статичен IP, DNS доставчиците, bucket, backup/restore теста, alert адреса, датите на двата сертификата и командата за IAP вход. При следващ разговор започни от този запис и [HANDOFF](../HANDOFF.md), без да търсиш отново имената.

Когато добавиш приложение с истинска SQLite база, преди реални данни направи **периодичен съгласуван backup извън VM, аларма за пропуснат backup и restore тест**; свържи `/health` със самото приложение. Тези задачи не се изпълняват от сегашния `start.sh` и не са доказани от пробната база. [План за приложението и възстановяването](sqlite-and-backups.md).

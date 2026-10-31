# Docker да изчаква data disk при рестарт

Това е подготвена процедура за Ubuntu VM с data disk, монтиран на `/srv/cloud-app-data`. Изпълнява се **във VM през IAP**, когато операторът е готов за проверка и последващ рестарт. Примерните имена и домейн се заменят с локалните реални стойности. Защитата още не е инсталирана само защото този файл съществува.

## 1. Провери диска и съществуващите настройки

```sh
findmnt --mountpoint /srv/cloud-app-data
lsblk -f
sudo systemctl cat docker.service
sudo systemctl is-enabled docker.service
```

`findmnt` трябва да покаже отделния data disk на точно този mount point; сравни устройството и UUID с локалния операторски запис. Docker трябва да е `enabled`. Ако дискът не е правилният или не е монтиран, спри и поправи монтирането. Mountpoint проверката по-долу установява, че има монтирана файлова система, но сама по себе си **не проверява нейния UUID**.

## 2. Инсталирай guard-а без рестарт на Docker

Изпълни целия блок. Той спира при грешка и няма да замени съществуващ файл със същото име:

```sh
(
  set -e
  set -o pipefail
  findmnt --mountpoint /srv/cloud-app-data
  if sudo test -e /etc/systemd/system/docker.service.d/10-require-data-disk.conf; then
    echo 'Guard файлът вече съществува. Прегледай го, преди да продължиш.' >&2
    exit 1
  fi
  sudo install -d -m 0755 /etc/systemd/system/docker.service.d
  printf '%s\n' '[Unit]' 'RequiresMountsFor=/srv/cloud-app-data' '[Service]' 'ExecStartPre=/usr/bin/mountpoint -q /srv/cloud-app-data' | sudo tee /etc/systemd/system/docker.service.d/10-require-data-disk.conf >/dev/null
  sudo systemctl daemon-reload
  sudo systemd-analyze verify docker.service
  sudo systemctl cat docker.service
)
```

В края провери двата реда за `/srv/cloud-app-data` в drop-in секцията. `daemon-reload` зарежда настройката на systemd и **не рестартира** работещия Docker. `RequiresMountsFor=` задава зависимост от необходимото монтиране; `mountpoint -q` спира старта на Docker, ако пътят не е mount point. Виж и [оригиналния шаблон](../systemd/docker.service.d/10-require-data-disk.conf.example) и [операционната процедура](operations.md#start-docker-only-after-the-data-disk).

## 3. Тест с нормален рестарт

След като прегледаш резултата от стъпка 2, рестартирай VM с `sudo reboot`. Влез отново през Cloud Shell/IAP с командата от локалния операторски запис. На VM изпълни:

```sh
findmnt --mountpoint /srv/cloud-app-data
systemctl is-active docker.service
sudo docker ps
curl -fsS https://api.example.com/health; echo
curl -fsS https://api.example.com/gaz; echo
curl -fsS https://api.example.com/mas; echo
```

Замени примерния домейн. Очакваме правилния диск, `active`, Caddy и двата Node контейнера, после `healthy`, `hello from gaz` и `hello from mas`. Запиши резултата. Това проверява нормален старт с наличен диск; не доказва какво става при нарочно липсващ диск.

При проблем: `sudo systemctl status docker.service` и `sudo journalctl -u docker.service -b --no-pager` показват причината. Ако дискът липсва, възстанови правилното монтиране и после стартирай Docker с `sudo systemctl start docker.service`. Ако трябва временно да отмениш защитата, първо прегледай файла, после премахни само `/etc/systemd/system/docker.service.d/10-require-data-disk.conf` и изпълни `sudo systemctl daemon-reload`; преди ръчен старт на Docker задължително провери правилния диск.

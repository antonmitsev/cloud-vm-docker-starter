# Един поддомейн през Cloudflare Free, без преместване на основния DNS

Това е повторима схема за `api.example.com`, когато авторитетните nameserver-и на `example.com` трябва да останат при сегашния DNS доставчик. Купува се **отделен евтин домейн** (тук `example.net` е условен пример) и само той се добавя като активна зона в Cloudflare. Оригиналният сайт, пощата и останалите DNS записи на `example.com` не се местят.

Обикновеният [Cloudflare CNAME/partial setup](https://developers.cloudflare.com/dns/zone-setups/partial-setup/) за запазени външни nameserver-и изисква Business или Enterprise. Тук използваме [Cloudflare for SaaS](https://developers.cloudflare.com/cloudflare-for-platforms/cloudflare-for-saas/start/getting-started/) върху **Free** зона на втория домейн. Към октомври 2026 г. планът включва [100 custom hostnames](https://developers.cloudflare.com/cloudflare-for-platforms/cloudflare-for-saas/plans/); за активиране на услугата при не-Enterprise акаунт се изисква [метод за плащане](https://developers.cloudflare.com/cloudflare-for-platforms/cloudflare-for-saas/start/enable/). Покупката и подновяването на втория домейн се плащат отделно. Проверявай актуалните условия преди нова настройка.

```text
api.example.com → CNAME origin.example.net → Cloudflare → публичен IPv4 на VM
       DNS при стария доставчик       Free зона       Caddy / приложение
```

## Настройка

1. Регистрирай втори домейн при избран регистратор и го активирай в Cloudflare на Free план. **Само nameserver-ите на втория домейн** трябва да сочат към Cloudflare. Остави `example.com` при стария DNS доставчик.
2. В Cloudflare DNS за втория домейн създай `origin.example.net` като **Proxied** (оранжев облак) A запис към статичния IPv4 адрес на VM. В Cloudflare for SaaS задай този hostname като **Fallback Origin** и изчакай статус **Active**. При стандартния fallback Cloudflare изпраща към origin първоначалните `Host` и TLS SNI на `api.example.com`; Caddy трябва да обслужва този домейн с валиден сертификат. Използвай **Full (strict)** за TLS към origin. Виж [fallback origin](https://developers.cloudflare.com/cloudflare-for-platforms/cloudflare-for-saas/start/getting-started/) и [Host/SNI поведението](https://developers.cloudflare.com/cloudflare-for-platforms/cloudflare-for-saas/reference/connection-details/).
3. Добави `api.example.com` като **Custom Hostname** в Cloudflare for SaaS. При стария DNS доставчик добави точно показаните от Cloudflare TXT записи за собствеността на hostname и за сертификата. Това са отделни проверки; възможно е да има повече от един TXT запис за сертификата. Изчакай **Hostname: Active** и **Certificate: Active**. Виж [валидацията](https://developers.cloudflare.com/cloudflare-for-platforms/cloudflare-for-saas/domain-support/hostname-validation/).
4. Едва тогава при стария DNS доставчик замени A записа на `api.example.com` с **CNAME към `origin.example.net`**. За едно и също име не оставяй едновременно A и CNAME. Не променяй NS записите на `example.com` и останалите му имена. Публичният DNS трябва да върне Cloudflare адреси, а HTTPS отговорът — заглавка `cf-ray`.
5. В GCP VPC firewall създай входящо правило за TCP 80/443 **само от [актуалните IPv4 диапазони на Cloudflare](https://www.cloudflare.com/ips/)**, със същата VPC и target tag като старото уеб правило. След като провериш HTTPS през Cloudflare, **изключи** старото правило за `0.0.0.0/0` на 80/443. Остави SSH правилото за IAP отделно. При origin само с публичен IPv4 не са нужни IPv6 source ranges за връзката Cloudflare → VM. Ако origin получи публичен IPv6, прегледай IPv6 правилата отделно.

## Проверка и връщане назад

Замени примерните имена и IP адрес с реалните; `203.0.113.10` е само адрес за документация.

```sh
dig +short CNAME api.example.com
dig @1.1.1.1 api.example.com A +short
curl -i --max-time 10 https://api.example.com/health
curl --connect-timeout 5 --max-time 8 --resolve api.example.com:443:203.0.113.10 https://api.example.com/health
```

Очакване: първата команда показва CNAME към втория домейн; публичният A отговор съдържа Cloudflare IP адреси; нормалният HTTPS път връща `200 healthy` и `cf-ray`; директният опит към VM на 443 изтича по време. Провери по същия начин и порт 80. Ако след изключване на старото правило Cloudflare пътят спре, включи старото правило временно, поправи новото и повтори проверките.

## Сертификати и подновяване

За `api.example.com` има **две отделни TLS връзки**. Между посетителя и Cloudflare сертификатът е на Cloudflare for SaaS. Cloudflare обикновено издава [две съвместими версии — ECDSA и RSA](https://developers.cloudflare.com/cloudflare-for-platforms/cloudflare-for-saas/security/certificate-management/issue-and-validate/issue-certificates/) — и управлява подновяването им. За обикновен активен поддомейн, който продължава да сочи към SaaS зоната, Cloudflare може да валидира подновяването автоматично през HTTP дори ако първоначално сме използвали TXT. Ако автоматичната проверка не е възможна, [новият сертификат може да изисква нови TXT стойности](https://developers.cloudflare.com/cloudflare-for-platforms/cloudflare-for-saas/security/certificate-management/issue-and-validate/renew-certificates/); следи статуса **Certificate: Active**.

Между Cloudflare и VM Caddy представя **своя** сертификат за `api.example.com` и [го подновява автоматично](https://caddyserver.com/docs/automatic-https). При HTTP-01 проверка заявката по порт 80 трябва да стига през Cloudflare до Caddy; TLS-ALPN-01 завършва на Cloudflare и не достига директно до Caddy. Caddy може да пробва повече от един ACME метод, но следи логовете и срока на origin сертификата, защото успешно работещ edge сертификат не доказва, че origin сертификатът се подновява. Използвай **Full (strict)**, за да валидира Cloudflare сертификата на VM. Cloudflare Universal SSL за втория домейн е допълнителен edge сертификат за неговите имена, ако е включен; той не замества custom-hostname или Caddy сертификата за API.

Провери датите на edge сертификата от външна машина, а на origin сертификата — **от самата VM** през loopback, който не минава през GCP firewall. Замени примерния домейн:

```sh
# Външна машина: сертификатът, който вижда посетителят от Cloudflare.
openssl s_client -connect api.example.com:443 -servername api.example.com </dev/null 2>/dev/null | openssl x509 -noout -subject -dates

# На VM: сертификатът, който Caddy подава към Cloudflare.
openssl s_client -connect 127.0.0.1:443 -servername api.example.com </dev/null 2>/dev/null | openssl x509 -noout -subject -dates
```

Ограничението по Cloudflare IP адреси спира директния HTTP/HTTPS достъп от други мрежи, но тези адреси се споделят между клиенти на Cloudflare. То не удостоверява конкретния Cloudflare акаунт и не поставя таван на GCP разходите от валидни заявки през проксито. Следи бюджета, трафика и наличните за плана WAF/rate-limit настройки. При промяна на [списъка с Cloudflare IP адреси](https://www.cloudflare.com/ips/) обнови GCP правилото, за да не прекъснеш сайта.

За наблюдаваното състояние на този проект виж [инвентара](gcp-current-state.md); за историята на ръчната настройка виж [човешкия запис](gcp-journey-bg.md).

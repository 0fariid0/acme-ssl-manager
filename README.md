# ACME SSL Manager

یک اسکریپت منودار و ساده برای مدیریت SSL روی سرورهای لینوکسی با استفاده از `acme.sh`.

این ابزار برای دیدن، گرفتن، تمدید، حذف و بکاپ گرفتن از SSLها ساخته شده و برای سرورهایی که با x-ui، 3x-ui، HAProxy، Nginx، Apache یا Caddy کار می‌کنند مناسب است.

> منوی خود اسکریپت انگلیسی است، چون خیلی از ترمینال‌های لینوکس فارسی را درست نمایش نمی‌دهند. توضیحات این فایل فارسی است.

---

## آدرس پروژه

```bash
https://github.com/0fariid0/acme-ssl-manager
```

---

## اجرای مستقیم از گیت‌هاب

بعد از آپلود فایل‌ها روی گیت‌هاب، روی سرور بزن:

```bash
bash <(curl -Ls https://raw.githubusercontent.com/0fariid0/acme-ssl-manager/main/ssl-manager.sh)
```

---

## نصب به‌صورت دستور دائمی

برای اینکه بعداً فقط با دستور `sslmgr` اجرا شود:

```bash
curl -Ls -o /usr/local/bin/sslmgr https://raw.githubusercontent.com/0fariid0/acme-ssl-manager/main/ssl-manager.sh
chmod +x /usr/local/bin/sslmgr
sslmgr
```

بعد از نصب، هر وقت خواستی منو باز شود:

```bash
sslmgr
```

---

## گرفتن SSL با حالت سریع و پیش‌فرض

در نسخه جدید، گرفتن SSL دیگر چندین سؤال نمی‌پرسد. از منو گزینه زیر را بزن:

```text
2) Quick issue certificate (default)
```

بعد فقط دامنه را وارد کن:

```text
example.com
```

اگر چند دامنه یا ساب‌دامنه داری، با فاصله یا کاما وارد کن:

```text
example.com www.example.com sub.example.com
```

یا:

```text
example.com,www.example.com,sub.example.com
```

حالت سریع به‌صورت خودکار این تنظیمات را استفاده می‌کند:

```text
Challenge : HTTP-01 standalone
Port      : 80
Key type  : ECC ec-256
Web stop  : Auto, enabled
Network   : Auto IPv4/IPv6 detection
Install   : /etc/acme-ssl-manager/certs/DOMAIN/
```

یعنی دیگر نمی‌پرسد HTTP یا ALPN، ECC یا RSA، خاموش کردن Apache/Nginx/HAProxy یا نه. همه چیز روی حالت پیشنهادی انجام می‌شود.

---

## گرفتن SSL فقط با یک دستور

اگر دستور `sslmgr` را نصب کرده باشی، می‌توانی بدون باز کردن منو SSL بگیری:

```bash
sslmgr issue example.com
```

برای چند دامنه:

```bash
sslmgr issue example.com www.example.com sub.example.com
```

یا حتی مستقیم از گیت‌هاب:

```bash
bash <(curl -Ls https://raw.githubusercontent.com/0fariid0/acme-ssl-manager/main/ssl-manager.sh) issue example.com
```

---

## حالت پیشرفته

اگر بخواهی خودت نوع Challenge، نوع کلید یا خاموش/روشن شدن سرویس‌ها را انتخاب کنی، از منو گزینه زیر را بزن:

```text
3) Advanced issue certificate
```

در این حالت می‌توانی انتخاب کنی:

```text
1) HTTP-01 standalone on port 80
2) TLS-ALPN-01 standalone on port 443
```

و همین‌طور نوع کلید:

```text
1) ECC ec-256
2) RSA 2048
```

---

## منوی اصلی

```text
1) View certificates and remaining time
2) Quick issue certificate (default)
3) Advanced issue certificate
4) Renew one certificate
5) Renew all certificates
6) Remove certificate
7) Show cert/key paths
8) Backup certificates
9) Diagnostics
10) Install/Update local command: sslmgr
11) Upgrade acme.sh
12) Register/Update Let's Encrypt account email
13) Network/TLS repair & ACME preflight
0) Exit
```

---

## امکانات

- نصب خودکار `acme.sh`
- نصب ابزارهای موردنیاز مثل `curl`، `openssl`، `socat` و `ca-certificates`
- گرفتن SSL سریع فقط با وارد کردن دامنه
- گرفتن SSL پیشرفته با تنظیمات دستی
- نمایش SSLهای موجود روی سرور
- نمایش تاریخ انقضا و زمان باقی‌مانده هر SSL
- تمدید یک SSL مشخص
- تمدید همه SSLها
- حذف SSL از acme.sh و مسیر نصب‌شده
- گرفتن بکاپ از SSLها
- نمایش مسیر `private.key` و `fullchain.pem`
- بررسی پورت‌های 80 و 443
- بررسی سرویس‌های فعال مثل Apache، Nginx، Caddy و HAProxy
- خاموش‌کردن موقت سرویس‌های وب هنگام گرفتن SSL
- روشن‌کردن دوباره فقط همان سرویس‌هایی که اسکریپت خاموش کرده است
- تعمیر خودکار مشکل‌های رایج شبکه، TLS و CA certificate
- تشخیص مشکل IPv6 و استفاده خودکار از IPv4 با `--request-v4`

---

## مسیر ذخیره SSLها

SSLهای نصب‌شده توسط این ابزار در مسیر زیر قرار می‌گیرند:

```bash
/etc/acme-ssl-manager/certs/DOMAIN/
```

مثلاً برای دامنه `example.com`:

```bash
/etc/acme-ssl-manager/certs/example.com/private.key
/etc/acme-ssl-manager/certs/example.com/fullchain.pem
/etc/acme-ssl-manager/certs/example.com/cert.pem
/etc/acme-ssl-manager/certs/example.com/ca.pem
```

برای بیشتر پنل‌ها معمولاً همین دو مسیر کافی است:

```bash
/etc/acme-ssl-manager/certs/example.com/private.key
/etc/acme-ssl-manager/certs/example.com/fullchain.pem
```

---

## تمدید SSL

برای تمدید یک SSL:

```text
4) Renew one certificate
```

برای تمدید همه SSLها:

```text
5) Renew all certificates
```

`acme.sh` معمولاً خودش کرون‌جاب تمدید خودکار نصب می‌کند، اما این منو برای مدیریت دستی و بررسی راحت‌تر است.

---

## حذف SSL

برای حذف SSL:

```text
6) Remove certificate
```

اسکریپت قبل از حذف تأیید می‌گیرد. اگر لازم باشد، می‌توانی قبل از حذف SSL را revoke هم بکنی.

---

## بکاپ گرفتن

برای گرفتن بکاپ از SSLها:

```text
8) Backup certificates
```

بکاپ‌ها در این مسیر ذخیره می‌شوند:

```bash
/etc/acme-ssl-manager/backups/
```

---

## استفاده برای x-ui / 3x-ui / HAProxy / Nginx

بعد از گرفتن SSL، از منو گزینه زیر را بزن:

```text
7) Show cert/key paths
```

بعد مسیرها را داخل پنل یا کانفیگ خودت قرار بده:

```bash
/etc/acme-ssl-manager/certs/DOMAIN/private.key
/etc/acme-ssl-manager/certs/DOMAIN/fullchain.pem
```

---

## حل خطای Could not get nonce / curl error 35

اگر هنگام گرفتن SSL خطایی شبیه این دیدی:

```text
Could not get nonce
curl error code: 35
Le_OrderFinalize not found
```

این خطا معمولاً قبل از مرحله بررسی دامنه رخ می‌دهد. یعنی سرور هنوز به مرحله تأیید پورت 80 یا 443 نرسیده و مشکل از اتصال خروجی سرور به API لتسنکریپت، TLS، CA certificate، ساعت سرور یا IPv6 است.

برای تعمیر از منو بزن:

```text
13) Network/TLS repair & ACME preflight
```

اگر IPv4 کار کند ولی IPv6 خراب باشد، اسکریپت خودش به صورت خودکار از این حالت استفاده می‌کند:

```bash
--request-v4 --listen-v4
```

اگر هم IPv4 و هم IPv6 به API لتسنکریپت وصل نشوند، اسکریپت قبل از خاموش‌کردن سرویس‌ها عملیات را متوقف می‌کند تا سرور الکی دچار قطعی نشود.

---

## تست دستی اتصال به لتسنکریپت

اگر هنوز مشکل داشتی، این دستورها را روی سرور تست کن:

```bash
curl -Iv https://acme-v02.api.letsencrypt.org/directory
curl -4Iv https://acme-v02.api.letsencrypt.org/directory
curl -6Iv https://acme-v02.api.letsencrypt.org/directory
curl -4Iv https://acme-v02.api.letsencrypt.org/acme/new-nonce
curl -6Iv https://acme-v02.api.letsencrypt.org/acme/new-nonce
```

اگر هیچ‌کدام جواب نداد، مشکل از شبکه خروجی سرور، DNS، فایروال دیتاسنتر، تحریم/فیلتر مسیر، CA certificate یا ساعت سرور است.

---

## آپدیت اسکریپت

اگر فایل جدید را روی گیت‌هاب آپلود کردی و قبلاً دستور `sslmgr` را نصب کرده بودی، برای آپدیت بزن:

```bash
curl -Ls -o /usr/local/bin/sslmgr https://raw.githubusercontent.com/0fariid0/acme-ssl-manager/main/ssl-manager.sh
chmod +x /usr/local/bin/sslmgr
sslmgr
```

---

## نکته‌های مهم

- دامنه باید به IP همین سرور اشاره کند.
- برای حالت سریع، پورت عمومی 80 باید از بیرون باز باشد.
- اگر Cloudflare روشن است، برای گرفتن SSL بهتر است موقتاً Proxy را خاموش کنی و رکورد را روی DNS Only بگذاری.
- اگر سرور IPv6 خراب دارد، اسکریپت تلاش می‌کند با IPv4 ادامه دهد.
- اگر اتصال خروجی سرور به لتسنکریپت قطع باشد، هیچ اسکریپتی نمی‌تواند SSL بگیرد تا مشکل شبکه حل شود.

---

## License

MIT

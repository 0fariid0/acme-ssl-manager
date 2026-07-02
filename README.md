# ACME SSL Manager

یک اسکریپت منودار، ساده و مدرن برای مدیریت SSL با `acme.sh`.

منوی داخل ترمینال انگلیسی است تا روی لینوکس و سرورهایی که فارسی را درست نشان نمی‌دهند، مشکل نمایش نداشته باشد. توضیحات این فایل فارسی نوشته شده است.

---

#### اجرای مستقیم از گیت‌هاب

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

یا:

```bash
sudo bash ssl-manager.sh
```

### نصب لوکال به‌صورت دستور دائمی

برای اینکه بعداً فقط با دستور `sslmgr` اجرا شود:

```bash
sudo install -m 755 ssl-manager.sh /usr/local/bin/sslmgr
sslmgr
```

---

## امکانات اصلی

- گرفتن SSL فقط با وارد کردن دامنه
- نمایش SSLهای گرفته‌شده در بالای منو
- نمایش زمان باقی‌مانده هر SSL
- تمدید دستی یک SSL
- نمایش مسیر `private.key` و `fullchain.pem`
- آپدیت خودکار `acme.sh`
- تست و تعمیر خودکار Network/TLS هنگام شروع اسکریپت
- خاموش و روشن کردن موقت Apache / Nginx / Caddy / HAProxy هنگام گرفتن SSL
- ذخیره مرتب گواهی‌ها در مسیر استاندارد

---

## ظاهر منو

منو فقط گزینه‌های ضروری را دارد و شماره‌ها مرتب هستند:

```text
[ 1]  Quick issue certificate       default, one-question SSL issue
[ 2]  Renew one certificate         pick a domain and renew
[ 3]  Show cert/key paths           copy paths for panels
[ 4]  Upgrade acme.sh               update the ACME client
[ 0]  Exit                          close manager
```

بالای منو، داشبورد SSLها نمایش داده می‌شود. نمونه:

```text
Certificates Dashboard
────────────────────────────────────────────────────────────────────────
  Managed: 2    Active:1    Soon:1    Expired:0    Check:0

  #   Domain                          Key       Remaining      Status     Expires
  1   example.com                     ec-256    87d 4h         ACTIVE     2026-09-28 10:20:00 UTC
  2   sub.example.com                 ec-256    12d 1h         SOON       2026-07-14 09:30:00 UTC
```

اگر هنوز SSL نگرفته باشی، بالای منو پیام راهنما نمایش داده می‌شود و گزینه 1 برای گرفتن اولین SSL معرفی می‌شود.

---

## گرفتن SSL سریع

از منو گزینه 1 را بزن:

```text
[ 1] Quick issue certificate
```

بعد فقط دامنه را وارد کن:

```text
example.com
```

برای چند دامنه یا ساب‌دامنه:

```text
example.com www.example.com sub.example.com
```

یا:

```text
example.com,www.example.com,sub.example.com
```

حالت سریع خودش این تنظیمات را اعمال می‌کند:

```text
Challenge : HTTP-01 standalone
Port      : 80
Key type  : ECC ec-256
Web stop  : Auto enabled
Network   : Auto IPv4/IPv6 detection
Install   : /etc/acme-ssl-manager/certs/DOMAIN/
```

یعنی دیگر سؤال‌های اضافه مثل نوع Challenge، نوع کلید، خاموش کردن وب‌سرور یا Force IPv4 پرسیده نمی‌شود.

---

## گرفتن SSL با یک دستور

اگر `sslmgr` را نصب کرده باشی:

```bash
sslmgr issue example.com
```

برای چند دامنه:

```bash
sslmgr issue example.com www.example.com sub.example.com
```

---

## تمدید یک SSL

از منو گزینه 2 را بزن:

```text
[ 2] Renew one certificate
```

بعد از نمایش لیست SSLها، شماره دامنه را انتخاب کن.

در این حالت اسکریپت خودش این کارها را انجام می‌دهد:

- اتصال به Let’s Encrypt را بررسی می‌کند.
- اگر لازم باشد Network/TLS را تعمیر می‌کند.
- اگر IPv6 مشکل داشته باشد و IPv4 سالم باشد، خودش از IPv4 استفاده می‌کند.
- وب‌سرورهای فعال را فقط در صورت نیاز موقتاً خاموش می‌کند.
- بعد از پایان عملیات، همان سرویس‌هایی را که خودش خاموش کرده دوباره روشن می‌کند.

---

## نمایش مسیر فایل‌های SSL

از منو گزینه 3 را بزن:

```text
[ 3] Show cert/key paths
```

مسیرهای اصلی برای x-ui، 3x-ui، HAProxy، Nginx یا پنل‌ها معمولاً این‌ها هستند:

```bash
/etc/acme-ssl-manager/certs/DOMAIN/private.key
/etc/acme-ssl-manager/certs/DOMAIN/fullchain.pem
```

مثال:

```bash
/etc/acme-ssl-manager/certs/example.com/private.key
/etc/acme-ssl-manager/certs/example.com/fullchain.pem
```

---

## آپدیت acme.sh

از منو گزینه 4 را بزن:

```text
[ 4] Upgrade acme.sh
```

این گزینه فقط خود `acme.sh` را آپدیت می‌کند.

---

## مسیر ذخیره SSLها

SSLهایی که توسط این ابزار نصب می‌شوند، در این مسیر ذخیره می‌شوند:

```bash
/etc/acme-ssl-manager/certs/DOMAIN/
```

داخل این مسیر معمولاً این فایل‌ها ساخته می‌شوند:

```text
private.key
fullchain.pem
cert.pem
ca.pem
```

---

## تست و تعمیر خودکار Network/TLS

گزینه دستی تعمیر شبکه از منو حذف شده و حالا اسکریپت هنگام شروع خودش این موارد را بررسی می‌کند:

- نصب بودن ابزارهای مورد نیاز مثل `curl`، `openssl`، `ca-certificates` و `socat`
- اتصال به API لتسنکریپت
- اتصال به endpoint مربوط به `new-nonce`
- سالم بودن IPv4 و IPv6 برای درخواست‌های ACME
- درست بودن ساعت سرور با NTP
- آماده بودن `acme.sh`

اگر اتصال خروجی سرور به Let’s Encrypt خراب باشد، اسکریپت قبل از خاموش کردن Apache/Nginx/HAProxy عملیات را متوقف می‌کند تا سرویس‌های سرور بی‌دلیل قطع نشوند.

---

## نکته‌های مهم

- دامنه باید به IP همین سرور اشاره کند.
- برای حالت سریع، پورت عمومی 80 باید از بیرون باز باشد.
- اگر Cloudflare روشن است، برای گرفتن SSL بهتر است موقتاً Proxy را خاموش کنی و رکورد را روی DNS Only بگذاری.
- اگر Apache، Nginx، Caddy یا HAProxy روی پورت 80 فعال باشند، اسکریپت هنگام گرفتن SSL آن‌ها را موقتاً خاموش می‌کند و بعد از پایان کار دوباره روشن می‌کند.
- اگر دیتاسنتر یا فایروال خروجی سرور اتصال به Let’s Encrypt را بسته باشد، تا وقتی مشکل شبکه حل نشود SSL گرفته نمی‌شود.

---

## خطای Could not get nonce / curl error 35

اگر خطایی مثل این دیدی:

```text
Could not get nonce
curl error code: 35
Le_OrderFinalize not found
```

معمولاً یعنی سرور قبل از مرحله بررسی دامنه، نتوانسته درست به API لتسنکریپت وصل شود. دلیل‌های رایج:

- مشکل خروجی HTTPS سرور
- مشکل IPv6
- مشکل CA certificate
- اشتباه بودن ساعت سرور
- محدودیت دیتاسنتر یا فایروال
- مشکل DNS خروجی سرور

اسکریپت این مورد را هنگام شروع بررسی می‌کند و اگر قابل تعمیر باشد، خودش تلاش می‌کند تعمیر کند.

برای تست دستی:

```bash
curl -Iv https://acme-v02.api.letsencrypt.org/directory
curl -4Iv https://acme-v02.api.letsencrypt.org/directory
curl -6Iv https://acme-v02.api.letsencrypt.org/directory
curl -4Iv https://acme-v02.api.letsencrypt.org/acme/new-nonce
curl -6Iv https://acme-v02.api.letsencrypt.org/acme/new-nonce
```

---

## حذف رنگ‌ها در ترمینال

اگر روی یک ترمینال خاص رنگ‌ها خوب نمایش داده نشد، می‌توانی با `NO_COLOR=1` اجرا کنی:

```bash
NO_COLOR=1 sudo bash ssl-manager.sh
```

---

## License

MIT

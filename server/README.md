# Сервер ИИ для приложения «АртСтрой»

Приложение больше не хранит ключи ИИ. Оно обращается только к этому серверу, а ключи GigaChat / YandexGPT лежат в файле `.env` на сервере. Сервер ставит дневные лимиты на каждую установку приложения, поэтому чужие люди не смогут потратить ваш баланс.

## Что умеет
| Запрос приложения | Что делает |
|---|---|
| `POST /v1/ai/chat` | СтройПомощник, перевод, ответы (с потоковой выдачей текста) |
| `POST /v1/ai/json` | Дизайн по планировке, счёт предметов по фото (JSON по схеме) |
| `POST /v1/ai/image-edit` | Фотореализм по точной 3D‑модели (FLUX / GPT Image, если ключи заданы) |
| `POST /v1/ai/image` | Картинка по описанию (Kandinsky через GigaChat или YandexART) |
| `GET /v1/ai/capabilities` | Что сейчас подключено + остаток лимитов |

Если первый ИИ недоступен, сервер сам отвечает через второй.

## Установка на VPS (Timeweb Cloud, Selectel, REG.RU — Ubuntu 22/24)
1. Купите VPS (1 vCPU, 1–2 ГБ RAM достаточно) и домен или поддомен, например `ai.sochi-art.com`. В DNS сделайте A‑запись домена на IP сервера.
2. Подключитесь по SSH и установите Docker:
   ```
   curl -fsSL https://get.docker.com | sh
   ```
3. Скопируйте папку `server` на VPS (например, `scp -r server root@IP:/opt/artstroy-ai`).
4. На сервере:
   ```
   cd /opt/artstroy-ai
   cp .env.example .env
   nano .env            # вставьте ключи
   nano Caddyfile       # замените ai.example.ru на свой домен
   docker compose up -d --build
   ```
5. Проверка: откройте `https://ваш-домен/health` — должно быть `{"ok":true}`.
6. В Xcode откройте `AIServer.plist` и впишите `https://ваш-домен` (и `APP_TOKEN`, если задали). Соберите приложение.

Логи: `docker compose logs -f ai`. Обновление: заменить файлы и `docker compose up -d --build`.

## Ключи
- **GigaChat**: developers.sber.ru → проект GigaChat API → «Ключ авторизации» (Authorization key). Для ИП/компании выберите scope `GIGACHAT_API_B2B` или `GIGACHAT_API_CORP`.
- **YandexGPT**: console.yandex.cloud → каталог (его ID = `YANDEX_FOLDER_ID`) → сервисный аккаунт с ролями `ai.languageModels.user` и `ai.imageGeneration.user` → «Создать API‑ключ».

## Проверка кода
`npm test` — тесты с имитацией GigaChat и Yandex (без реальных ключей).

## hh.ru: заявки → вакансии, отклики и чат в приложении
1. В `.env` заполните блок hh.ru: `HH_CLIENT_ID`, `HH_CLIENT_SECRET` (из dev.hh.ru), `HH_ADMIN_KEY` (любой длинный пароль), `PUBLIC_URL`.
2. `HH_REDIRECT_URI` должен совпадать с Redirect URI в dev.hh.ru: `https://pastura.2-26-100-30.sslip.io/v1/auth/hh/callback`. Значит запросы `/v1/auth/hh/*` и `/v1/hh/*` на этом домене должны попадать в этот сервер (см. ниже).
3. Подключение аккаунта (один раз): откройте в браузере `https://ваш-домен/v1/auth/hh/start?key=HH_ADMIN_KEY`, войдите на hh.ru как работодатель «АртСтрой» и разрешите доступ.
4. Проверка: `https://ваш-домен/v1/hh/status?key=HH_ADMIN_KEY` — покажет аккаунт и доступные публикации.

Как работает: клиент создаёт заявку в приложении → сервер публикует вакансию «проектная работа» на hh.ru (только бесплатной публикацией, если не задано `HH_PUBLICATION=any`; не больше `HH_MAX_PER_DAY` в день) → отклики и чат с соискателями видны в заявке в приложении. Контакты, фото и возраст соискателей в приложение не передаются.

hh.ru требует, чтобы сервер работал в России.

### Если на домене уже работает другой сервер
Caddy (маршруты hh и ИИ — сюда, всё остальное — в старый сервер на порту 3000, замените на свой):
```
pastura.2-26-100-30.sslip.io {
	@new path /v1/ai/* /v1/hh/* /v1/auth/hh/* /v1/avito/* /v1/auth/avito/* /v1/market/*
	reverse_proxy @new 127.0.0.1:8080 { flush_interval -1 }
	reverse_proxy 127.0.0.1:3000
}
```
nginx:
```
location ~ ^/v1/(ai|hh|avito|market|auth/hh|auth/avito)/ { proxy_pass http://127.0.0.1:8080; proxy_buffering off; proxy_read_timeout 300s; }
```

## Avito: заявки → вакансии Avito Работа, отклики и чат в приложении
1. В приложении Avito (developers.avito.ru) укажите Redirect URL `https://ваш-домен/v1/auth/avito/callback`.
2. В `.env` впишите `AVITO_CLIENT_ID` и `AVITO_CLIENT_SECRET`, затем `docker compose up -d --force-recreate ai`.
3. Подключение (ключ администратора тот же, что для hh.ru): `https://ваш-домен/v1/auth/avito/start?key=HH_ADMIN_KEY`.
4. Проверка: `https://ваш-домен/v1/avito/status?key=HH_ADMIN_KEY`.

Вакансии публикуются только из купленного пакета размещений Avito Работа (`AVITO_BILLING=package`). Для Messenger API у Avito может требоваться тариф для бизнеса.

## Рыночные цены по городам
Приложение запрашивает `GET /v1/market/price-book?city=&region=&lat=&lon=`. Сервер ищет прайс города, затем региона, затем ближайшего города в радиусе 300 км, затем общий по России (`scope: national`). Если ничего не нашлось, возвращается 404, и приложение считает по базовым ориентирам с пометкой.

Как собрать прайс города:
1. Создайте `market-observations/<город>.csv`. В первых строках опишите место: `# city=Сочи`, `# region=Краснодарский край`, `# lat=43.585`, `# lon=39.723`.
2. Дальше строка заголовка и сами предложения: `code,kind,price,source,url,date`. `code` берётся из `market-prices/_lines.template`, `kind` — `material` или `labor`, цена указывается за единицу строки.
3. Выполните `node scripts/build-price-book.js market-observations/<город>.csv`. Получится `market-prices/<город>.json`: медиана, диапазон P25–P75, число предложений. Выбросы отсекаются по межквартильному размаху, дубли одной ссылки и предложения старше 120 дней не учитываются.

## Подрядчики-партнёры
После каждой сметы приложение показывает до трёх партнёров города (если в городе никого нет, то партнёров региона): `GET /v1/partners?city=&region=&category=`.
Категории: `house`, `gazebo`, `metal` (полные сметы), `foundation`, `walls`, `roof`, `finishing`, `outdoor` (калькуляторы) или `all`.

Список партнёров задаётся целиком (ключ — `PARTNERS_ADMIN_KEY` в `.env`):
```
curl -X PUT https://ваш-домен/v1/admin/partners -H "x-admin-key: КЛЮЧ" -d '{"partners":[
 {"id":"beton-yug","name":"Бетон-Юг","description":"Фундаменты и монолит","cities":["Сочи"],"categories":["house","foundation"],
  "phone":"+7 900 000-00-00","whatsapp":"79000000000","site":"beton-yug.ru","rating":4.8,"priority":1,
  "advertiser":"ООО «Бетон-Юг»","erid":""}]}'
```
`GET /v1/admin/partners` с тем же ключом возвращает список и статистику по дням: показы и нажатия «WhatsApp», «Позвонить», «Сайт».

## Ежедневное обновление цен
Каждый день в 05:00 МСК таймер `artstroy-prices.timer` запускает `scripts/collect-prices.mjs`:
1. Список городов: все файлы `market-observations/*.csv` и до двух новых городов (`NEW_CITIES_PER_DAY`), из которых чаще всего просили цены, а прайса ещё не было. Сервер пишет такие запросы в `data/requested-cities.json`.
2. По каждому городу Claude (`claude -p`, только веб-поиск, модель `COLLECT_MODEL`, по умолчанию sonnet) ищет текущие предложения по позициям сметы и отвечает строками CSV.
3. Каждая строка проверяется: известный код, тип material/labor, число, ссылка, без повтора за день. Подходящие строки дописываются с сегодняшней датой.
4. Прайс пересобирается по последним `MAX_AGE_DAYS` дням (по умолчанию 30): медиана, вилка P25–P75, отсев выбросов. Сервер подхватывает новый файл в течение минуты, приложение — при следующем открытии.

Журнал: `data/collect.log`. Запустить вручную: `systemctl start artstroy-prices`. Один город: `node scripts/collect-prices.mjs sochi`.
Авито в сборе не участвует: он закрыт для автоматического поиска.

## Подключение на сервере без Docker
```
cp -r server /opt/artstroy-ai && mkdir -p /opt/artstroy-ai/data
printf 'PORT=3200\nDATA_DIR=/opt/artstroy-ai/data\nPARTNERS_ADMIN_KEY=%s\n' "$(openssl rand -base64 24)" > /etc/artstroy-ai.env && chmod 600 /etc/artstroy-ai.env
cp /opt/artstroy-ai/deploy/artstroy-*.service /opt/artstroy-ai/deploy/artstroy-prices.timer /etc/systemd/system/
cp /opt/artstroy-ai/deploy/artstroy-ai.caddy /etc/caddy/sites/   # заменить домен
systemctl daemon-reload && systemctl enable --now artstroy-ai artstroy-prices.timer && systemctl reload caddy
```
В приложении впишите домен в `AIServer.plist` → `MARKET_SERVER_URL`.

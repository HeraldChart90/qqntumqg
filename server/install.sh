#!/usr/bin/env bash
# АртСтрой: установка сервера (ИИ + hh.ru) на VPS одной командой. Запуск: bash install.sh
set -euo pipefail
DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$DIR"
say() { printf '\n\033[1;33m▶ %s\033[0m\n' "$*"; }
ok() { printf '\033[1;32m✓ %s\033[0m\n' "$*"; }
[ "$(id -u)" = 0 ] || { echo "Запустите от root: sudo bash install.sh"; exit 1; }

say "1/6 Docker"
if ! command -v docker >/dev/null 2>&1; then
  curl -fsSL https://get.docker.com | sh
fi
docker compose version >/dev/null 2>&1 || { apt-get update -y && apt-get install -y docker-compose-plugin; }
ok "Docker готов"

say "2/6 Адрес сервера"
IP="$(curl -4 -fsS -m 10 https://ifconfig.me 2>/dev/null || curl -4 -fsS -m 10 https://api.ipify.org)"
DOMAIN_DEFAULT="pastura.${IP//./-}.sslip.io"
DOMAIN="${DOMAIN:-$DOMAIN_DEFAULT}"
ok "IP $IP → домен $DOMAIN"
if [ "$DOMAIN" != "pastura.2-26-100-30.sslip.io" ]; then
  echo "⚠ В dev.hh.ru сейчас указан Redirect URI для 2.26.100.30. Для этого сервера поменяйте его на:"
  echo "   https://$DOMAIN/v1/auth/hh/callback"
fi

say "3/6 Настройки (.env)"
[ -f .env ] || cp .env.example .env
setenv() { # setenv KEY VALUE  — replace or append
  if grep -q "^$1=" .env; then sed -i "s|^$1=.*|$1=$2|" .env; else echo "$1=$2" >> .env; fi
}
getenv() { grep -E "^$1=" .env | head -1 | cut -d= -f2-; }
[ -n "$(getenv HH_ADMIN_KEY)" ] || setenv HH_ADMIN_KEY "$(head -c 24 /dev/urandom | od -An -tx1 | tr -d ' \n')"
setenv PUBLIC_URL "https://$DOMAIN"
setenv HH_REDIRECT_URI "https://$DOMAIN/v1/auth/hh/callback"
[ -n "$(getenv HH_CLIENT_ID)" ] || setenv HH_CLIENT_ID "${HH_CLIENT_ID:-MRE8N05U3INF2Q1VLPJ1EUPE5N6N1NB0GQ2ELB0B71EABJ72588OD5K1RG26DVVR}"
ok ".env готов"

say "4/6 Запуск"
mkdir -p data && chown -R 1000:1000 data   # the app runs as user "node" (uid 1000) inside the container
if ss -ltn '( sport = :443 )' | grep -q LISTEN; then
  # 443 уже занят старым сервером: запускаем только приложение и добавляем маршруты в существующий веб‑сервер.
  docker compose up -d --build ai
  if systemctl is-active --quiet nginx 2>/dev/null; then
    CONF="$(grep -rl "$DOMAIN\|sslip.io" /etc/nginx/sites-enabled /etc/nginx/conf.d 2>/dev/null | head -1 || true)"
    if [ -n "$CONF" ] && ! grep -q "artstroy-new" "$CONF"; then
      cp "$CONF" "$CONF.bak-artstroy"
      python3 - "$CONF" <<'PY'
import sys,re
p=sys.argv[1]; s=open(p).read()
block='''
    # artstroy-new: ИИ и hh.ru
    location ~ ^/v1/(ai|hh|avito|market|auth/hh|auth/avito)/ {
        proxy_pass http://127.0.0.1:8080;
        proxy_set_header Host $host;
        proxy_set_header X-Forwarded-For $remote_addr;
        proxy_buffering off;
        proxy_read_timeout 300s;
        client_max_body_size 20m;
    }
'''
m=re.search(r'listen\s+[^;]*443[^;]*;',s)
if not m: sys.exit("no 443 server block")
s=s[:m.end()]+block+s[m.end():]
open(p,'w').write(s)
PY
      nginx -t && systemctl reload nginx && ok "Маршруты добавлены в nginx ($CONF)"
    fi
  elif systemctl is-active --quiet caddy 2>/dev/null; then
    CF=/etc/caddy/Caddyfile
    if ! grep -q "artstroy-new" "$CF"; then
      cp "$CF" "$CF.bak-artstroy"
      python3 - "$CF" "$DOMAIN" <<'PY'
import sys
p,domain=sys.argv[1],sys.argv[2]; s=open(p).read()
i=s.find(domain)
if i<0: i=s.find('sslip.io')
j=s.find('{',i)
block='''
	# artstroy-new: ИИ и hh.ru
	@artstroy path /v1/ai/* /v1/hh/* /v1/auth/hh/* /v1/avito/* /v1/auth/avito/* /v1/market/*
	handle @artstroy {
		reverse_proxy 127.0.0.1:8080 {
			flush_interval -1
		}
	}
'''
s=s[:j+1]+block+s[j+1:]
open(p,'w').write(s)
PY
      caddy validate --config "$CF" >/dev/null && systemctl reload caddy && ok "Маршруты добавлены в Caddy"
    fi
  else
    echo "⚠ Порт 443 занят программой, которую я не узнал. Нужно направить пути /v1/ai/, /v1/hh/, /v1/auth/hh/, /v1/avito/, /v1/auth/avito/, /v1/market/ на 127.0.0.1:8080 (пример в README.md)."
  fi
else
  sed -i "s|^ai.example.ru {|$DOMAIN {|; s|^[a-z0-9.-]*sslip.io {|$DOMAIN {|" Caddyfile
  docker compose up -d --build
  ok "Сервер и HTTPS (Caddy) запущены"
fi

say "5/6 Ключ hh.ru"
if [ -z "$(getenv HH_CLIENT_SECRET)" ]; then
  printf "Вставьте Client Secret из dev.hh.ru и нажмите Enter: "
  read -r SECRET
  setenv HH_CLIENT_SECRET "$SECRET"
fi
printf "Ключ GigaChat (Enter — пропустить): "; read -r GIGA || true
[ -n "${GIGA:-}" ] && setenv GIGACHAT_AUTH_KEY "$GIGA"
docker compose up -d --force-recreate ai >/dev/null
sleep 3

say "6/6 Проверка"
if curl -fsS -m 10 http://127.0.0.1:8080/health >/dev/null; then ok "Сервер отвечает"; else echo "⚠ Сервер не отвечает: docker compose logs ai"; fi
curl -fsS -m 15 "https://$DOMAIN/health" >/dev/null 2>&1 && ok "HTTPS работает: https://$DOMAIN" || echo "⚠ https://$DOMAIN пока не отвечает (сертификат выпускается до минуты). Проверьте позже."
ADMIN="$(getenv HH_ADMIN_KEY)"
printf '\n\033[1;32mГОТОВО.\033[0m Откройте на Mac или iPhone ссылку и войдите в hh.ru как работодатель:\n\n   https://%s/v1/auth/hh/start?key=%s\n\nПроверка подключения: https://%s/v1/hh/status?key=%s\nСохраните эту ссылку — ключ администратора нужен для переподключения.\n' "$DOMAIN" "$ADMIN" "$DOMAIN" "$ADMIN"

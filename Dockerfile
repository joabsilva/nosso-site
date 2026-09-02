# Site estático do appnosso.com, servido pelo Caddy com HTTPS automático
# (Let's Encrypt). Build context: esta pasta (nosso/site/).
FROM caddy:2-alpine

COPY Caddyfile /etc/caddy/Caddyfile

# Falha o build já se o Caddyfile tiver erro de sintaxe.
RUN caddy validate --config /etc/caddy/Caddyfile --adapter caddyfile

# Só os HTML entram na imagem — Dockerfile/Caddyfile/compose/DEPLOY.md ficam de fora.
COPY *.html /srv/

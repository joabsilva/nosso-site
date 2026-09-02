# Deploy do site (Docker + Caddy + Let's Encrypt)

O site é estático (só HTML). O container roda o **Caddy**, que serve os arquivos
e cuida sozinho do **HTTPS** — pede e renova o certificado no Let's Encrypt
automaticamente, sem cron, sem certbot.

Arquivos desta pasta usados no deploy:

| Arquivo         | Pra que serve                                                        |
|-----------------|---------------------------------------------------------------------|
| `Dockerfile`    | monta a imagem: Caddy + os `.html`                                  |
| `Caddyfile`     | config do Caddy (domínio, headers, e-mail do ACME)                  |
| `compose.yaml`  | sobe o container, mapeia portas 80/443, guarda os certificados      |
| `.dockerignore` | garante que só `Caddyfile` + `*.html` entrem na imagem              |

---

## 1. Pré-requisitos

- Um servidor Linux com **Docker** e **Docker Compose v2** (`docker compose`, sem hífen).
  Instalar num Ubuntu/Debian limpo:
  ```bash
  curl -fsSL https://get.docker.com | sh
  ```
- As portas **80** e **443** livres e abertas no firewall / security group.
  Se já existe outro Nginx/Apache/Caddy escutando nelas, pare-o antes
  (`sudo systemctl stop nginx` etc.) — este container precisa das duas.
- **DNS**: um registro **A** de `appnosso.com` apontando pro IP público do servidor.
  (E um **AAAA** se o servidor tiver IPv6.) Confirme antes de subir:
  ```bash
  dig +short appnosso.com
  ```
  Tem que devolver o IP do servidor. O Let's Encrypt só emite o certificado
  depois que o domínio resolve pra máquina onde o Caddy está rodando.

---

## 2. Configurar

1. Abra `Caddyfile` e confirme o **e-mail** do ACME (linha `email ...`) — é onde o
   Let's Encrypt avisa se um certificado estiver perto de expirar sem renovar.
2. Se o domínio não for `appnosso.com`, troque nas duas ocorrências do `Caddyfile`.
3. (Opcional) Se quiser `www.appnosso.com` redirecionando pro domínio principal:
   crie o registro DNS de `www` **primeiro** e só então descomente o bloco
   `www.appnosso.com { ... }` no fim do `Caddyfile`.

---

## 3. Subir

Esta pasta é um repositório git próprio. Coloque-a no servidor de um destes jeitos:

**Via git** (depois de criar um repo remoto e rodar `git remote add origin <url>`
+ `git push -u origin main` aqui):

```bash
git clone <url-do-repo> /opt/site-appnosso
cd /opt/site-appnosso && docker compose up -d --build
```

**Sem remote, via rsync/scp** (`SEU_SERVIDOR` = o que você usa no `ssh`):

```bash
rsync -avz nosso/site/ root@SEU_SERVIDOR:/opt/site-appnosso/
# ou:  scp -r nosso/site root@SEU_SERVIDOR:/opt/site-appnosso
cd /opt/site-appnosso && docker compose up -d --build   # no servidor
```

Na primeira vez o Caddy leva alguns segundos pedindo o certificado. Acompanhe:

```bash
docker compose logs -f
```

Você quer ver linhas como `certificate obtained successfully` e
`serving initial configuration`. `Ctrl+C` sai do log (não derruba o container).

---

## 4. Verificar

```bash
curl -I https://appnosso.com                 # HTTP/2 200
curl -I http://appnosso.com                  # 308 -> https (redirect automático)
curl -sI https://appnosso.com/privacidade.html | head -1
```

No navegador: `https://appnosso.com` com cadeado válido. Cheque a validade do
certificado:

```bash
echo | openssl s_client -servername appnosso.com -connect appnosso.com:443 2>/dev/null \
  | openssl x509 -noout -issuer -dates
```

Deve dizer `issuer= ... Let's Encrypt`.

---

## 5. Atualizar o conteúdo

Editou algum `.html`? Commit + push aqui, e no servidor:

```bash
cd /opt/site-appnosso && git pull && docker compose up -d --build
```

Sem remote git, reenvie por `rsync`/`scp` (passo 3) e rode o `up -d --build`.

O `--build` regera a imagem com os HTML novos e troca o container. Os
**certificados não são afetados** (ficam no volume `caddy_data`, fora da imagem).

---

## 6. Operação do dia a dia

```bash
docker compose ps                    # status
docker compose logs -f --tail=100    # logs (acessos + erros)
docker compose restart               # reinicia o Caddy
docker compose down                  # para e remove o container (mantém os volumes)
```

**Backup dos certificados** (opcional — o Caddy re-emite sozinho, mas evita
bater no limite do Let's Encrypt se você recriar o servidor):

```bash
docker run --rm -v nosso-site_caddy_data:/data -v "$PWD":/backup alpine \
  tar czf /backup/caddy_data.tgz -C /data .
```

---

## 7. Se der problema

**`lookup ... on 127.0.0.53:53 ... connection refused` nos logs**
DNS do container quebrado (host usa `systemd-resolved`). Já vem resolvido pelo
bloco `dns:` no `compose.yaml`. Se voltar a acontecer, confirme que o bloco está
lá e recrie: `docker compose up -d --force-recreate`. Teste de dentro do container:
```bash
docker compose exec web wget -qO- https://acme-v02.api.letsencrypt.org/directory
```

**O certificado não é emitido / fica em "TLS handshake error"**
- `dig +short appnosso.com` aponta mesmo pra este servidor?
- As portas 80 **e** 443 estão abertas de fora? Teste de outra máquina:
  `curl -v http://appnosso.com`. O desafio do Let's Encrypt entra pela 80.
- Rodando atrás de CDN/proxy (Cloudflare)? Coloque em modo "DNS only" (nuvem
  cinza) até o certificado sair, ou configure o `Caddyfile` pro desafio DNS.

**Testar sem gastar o limite do Let's Encrypt** (são ~5 certificados/semana por
domínio): descomente a linha `acme_ca ...staging...` no bloco `{ }` do `Caddyfile`,
suba, confirme que funciona (o navegador vai acusar certificado inválido — normal
no staging), depois comente de novo e:
```bash
docker compose up -d --build --force-recreate
```

**Porta 80/443 ocupada** (`bind: address already in use`)
```bash
sudo ss -tlnp 'sport = :80 or sport = :443'
```
Pare o serviço que aparecer, ou mude o mapeamento em `compose.yaml` (aí precisa
de um proxy na frente — fora do escopo deste guia).

**Recomeçar do zero** (perde os certificados — use o staging antes):
```bash
docker compose down -v && docker compose up -d --build
```

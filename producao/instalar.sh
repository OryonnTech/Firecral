#!/usr/bin/env bash
# Instala o MCP "Firecrawl gratuito" na PRODUÇÃO. Rodar como root: sudo bash /opt/firecrawl-mcp/instalar.sh
# Pode rodar de novo: o que já existe é mantido. Não mexe em nenhum outro contêiner além de ligar o
# Traefik na rede nova borda-firecrawl. Desfazer: sudo bash /opt/firecrawl-mcp/desfazer.sh
set -euo pipefail
DIR=/opt/firecrawl-mcp
AUTH=/opt/auth-ecosan
HOST_PUBLICO=mcp-firecrawl.oryonntech.com
RECURSO="https://$HOST_PUBLICO/mcp"
PAPEL=firecrawl-leitura
EMAIL_DONO=daniel.coimbra@ecosan.com
VERSAO="${VERSAO:-v1.0.0}"
[ "$(id -u)" = 0 ] || { echo "Rode com sudo."; exit 1; }
cd "$DIR" || { echo "$DIR não existe: copie a pasta producao/ e os arquivos compose.yaml e seccomp_chrome.json para lá."; exit 1; }
for f in compose.yaml seccomp_chrome.json env.exemplo; do test -f "$f" || { echo "FALTA $DIR/$f"; exit 1; }; done
TRAEFIK=$(docker ps --format '{{.Names}}' | grep -i traefik | head -1)
[ -n "$TRAEFIK" ] || { echo "Não achei o contêiner do Traefik."; exit 1; }
mkdir -p /var/backups/firecrawl-mcp
REGISTRO=/var/backups/firecrawl-mcp/instalacao-$(date +%Y%m%d-%H%M%S).txt
echo "inicio $(date '+%d/%m/%Y %H:%M') versao=$VERSAO traefik=$TRAEFIK" > "$REGISTRO"

echo "== 1. Rede própria borda-firecrawl e Traefik ligado nela"
docker network inspect borda-firecrawl >/dev/null 2>&1 || { docker network create borda-firecrawl >/dev/null && echo "  [criada] rede"; echo "rede criada" >> "$REGISTRO"; }
if docker inspect -f '{{json .NetworkSettings.Networks}}' "$TRAEFIK" | grep -q '"borda-firecrawl"'; then echo "  [ok] Traefik já na rede"
else docker network connect borda-firecrawl "$TRAEFIK" && echo "  [ligado] Traefik na rede" && echo "traefik conectado" >> "$REGISTRO"; fi
echo "  ATENÇÃO: para valer depois de recriar o Traefik, a rede borda-firecrawl precisa entrar no compose dele (/docker/traefik)."

echo "== 2. Login (Keycloak, realm mcp): papel $PAPEL e destino do token"
if [ -d "$AUTH" ]; then
  ( cd "$AUTH"; set -a; . ./.env; set +a
    KC() { docker compose exec -T keycloak /opt/keycloak/bin/kcadm.sh "$@"; }
    KC config credentials --server http://localhost:8080 --realm master --user "$ADMIN_USUARIO" --password "$ADMIN_SENHA_INICIAL" >/dev/null
    KC get "roles/$PAPEL" -r mcp >/dev/null 2>&1 && echo "  [ok] papel" || { KC create roles -r mcp -s name=$PAPEL >/dev/null && echo "  [criado] papel $PAPEL"; }
    SCOPE_ID=$(KC get client-scopes -r mcp --fields id,name --format csv --noquotes | grep ',mcp-audiencia$' | cut -d, -f1)
    [ -n "$SCOPE_ID" ] || { echo "  [ERRO] escopo mcp-audiencia não existe"; exit 1; }
    if KC get "client-scopes/$SCOPE_ID/protocol-mappers/models" -r mcp --fields name --format csv --noquotes | grep -qx aud-mcp-firecrawl; then echo "  [ok] destino do token"
    else KC create "client-scopes/$SCOPE_ID/protocol-mappers/models" -r mcp -s name=aud-mcp-firecrawl -s protocol=openid-connect \
      -s protocolMapper=oidc-audience-mapper -s "config.\"included.custom.audience\"=$RECURSO" \
      -s 'config."access.token.claim"=true' -s 'config."id.token.claim"=false' >/dev/null && echo "  [criado] destino do token"; fi
    if KC get "client-scopes/$SCOPE_ID/scope-mappings/realm" -r mcp --fields name --format csv --noquotes | grep -qx $PAPEL; then echo "  [ok] papel no token"
    else RID=$(KC get "roles/$PAPEL" -r mcp --fields id --format csv --noquotes)
      KC create "client-scopes/$SCOPE_ID/scope-mappings/realm" -r mcp -b "[{\"id\":\"$RID\",\"name\":\"$PAPEL\"}]" && echo "  [criado] papel no token"; fi
    KC add-roles -r mcp --uusername "$EMAIL_DONO" --rolename $PAPEL 2>/dev/null && echo "  [ok] $PAPEL para o dono" || echo "  [aviso] não dei o papel ao dono (usuário não existe no realm mcp?)"
  )
  echo "keycloak ajustado" >> "$REGISTRO"
else echo "  [ERRO] $AUTH não existe"; exit 1; fi

echo "== 3. .env (segredo nunca aparece na tela)"
if [ ! -f .env ]; then
  sed "s/^MCP_ACCESS_TOKEN=.*/MCP_ACCESS_TOKEN=$(openssl rand -hex 32)/" env.exemplo > .env
  echo "  [criado] .env"
else echo "  [ok] .env mantido"; fi
chown root:root .env && chmod 600 .env

echo "== 4. Imagem e subida"
VERSAO="$VERSAO" docker compose pull -q
VERSAO="$VERSAO" docker compose up -d
for i in $(seq 1 45); do
  st=$(docker inspect -f '{{.State.Health.Status}}' firecrawl-mcp-firecrawl-mcp-1 2>/dev/null || echo "?")
  [ "$st" = healthy ] && break; sleep 2
done
echo "  saúde: $st"; echo "saude=$st" >> "$REGISTRO"

echo "== 5. Testes internos"
IP=$(docker inspect -f '{{(index .NetworkSettings.Networks "borda-firecrawl").IPAddress}}' firecrawl-mcp-firecrawl-mcp-1)
echo -n "  /saude (espera 200): "; curl -s -o /dev/null -w '%{http_code}\n' "http://$IP:8766/saude"
echo -n "  /mcp sem login (espera 401): "; curl -s -o /dev/null -w '%{http_code}\n' -X POST "http://$IP:8766/mcp" -H "Host: $HOST_PUBLICO"
echo -n "  leitor recusa endereço interno do Docker (espera 'recusado'): "
docker exec firecrawl-mcp-firecrawl-mcp-1 python3 -c "import json,urllib.request,urllib.error
r=urllib.request.Request('http://127.0.0.1:3002/v2/scrape',data=json.dumps({'url':'http://172.17.0.1/'}).encode(),headers={'content-type':'application/json'})
try:
 d=json.load(urllib.request.urlopen(r,timeout=20)); print('ALCANCOU - PARE' if d.get('success') and (d.get('data') or {}).get('markdown') else 'recusado')
except urllib.error.HTTPError:
 print('recusado')"
echo -n "  DNS público de $HOST_PUBLICO: "; getent hosts "$HOST_PUBLICO" >/dev/null && echo ok || echo "NÃO resolve: criar o registro na Cloudflare (proxy laranja ligado)"
echo "fim $(date '+%d/%m/%Y %H:%M')" >> "$REGISTRO"
echo
echo "Pronto. Registro: $REGISTRO. Desfazer: sudo bash $DIR/desfazer.sh"
echo "Conector no Claude: $RECURSO (login com o seu e-mail do MCP)."

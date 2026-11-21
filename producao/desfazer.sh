#!/usr/bin/env bash
# Tira o MCP "Firecrawl gratuito" da produção. Não mexe em nenhum outro sistema.
# O papel firecrawl-leitura e o destino do token no Keycloak ficam (não atrapalham); apagar à mão se quiser.
set -uo pipefail
[ "$(id -u)" = 0 ] || { echo "Rode com sudo."; exit 1; }
cd /opt/firecrawl-mcp || exit 1
docker compose down
TRAEFIK=$(docker ps --format '{{.Names}}' | grep -i traefik | head -1)
[ -n "$TRAEFIK" ] && docker network disconnect borda-firecrawl "$TRAEFIK" 2>/dev/null
docker network rm borda-firecrawl 2>/dev/null
echo "Removido $(date '+%d/%m/%Y %H:%M'). A pasta /opt/firecrawl-mcp e o .env continuam; apague à mão se quiser."

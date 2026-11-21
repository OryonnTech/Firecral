# MCP "Firecrawl gratuito" (Oryonn/ECOSAN)

Conector MCP para o Claude (nuvem, app, celular e Claude Code) ler sites públicos **de graça, sem créditos**, usando o [Firecrawl Local](https://github.com/firecrawl/firecrawl/tree/main/apps/local) (AGPL-3.0) rodando no nosso servidor.

> O repositório se chama `Firecral` (nome criado assim); a imagem e o serviço se chamam `firecrawl-mcp`.

## O que faz

| Ferramenta | O que faz | Limite |
|---|---|---|
| `ler_pagina` | Lê uma página (inclusive PDF/Office e páginas em JavaScript) e devolve markdown, links ou HTML | 120 mil caracteres por resposta |
| `listar_paginas` | Lista as URLs de um site (sitemap + página inicial) | até 1.000 |
| `ler_site` | Segue os links de um site e lê várias páginas | até 25 páginas, profundidade 3, respeita robots.txt |

Não faz busca na web, extração estruturada (json/summary), agent nem monitores: isso continua com a busca do Claude e o conector Firecrawl da conta (ordem na skill `ler-sites-com-firecrawl`).

## Segurança

- **Nada vai para a nuvem do Firecrawl**: `FIRECRAWL_CLOUD=off` na imagem, no compose e forçado de novo pelo `servidor.py` ao subir o motor (LGPD).
- **Só sites públicos**: o `servidor.py` recusa `localhost`, IPs privados/reservados, `.internal/.local/.lan`, usuário/senha na URL e esquemas que não sejam http/https; o Firecrawl Local (sem `--allow-private`) recusa de novo, inclusive após redirecionamento e DNS, e bloqueia metadados de nuvem.
- **Login por pessoa** (Keycloak `auth-ecosan`, realm `mcp`, papel `firecrawl-leitura`) ou token fixo de 32+ caracteres. Mesmo portão do `omie-mcp`.
- **Só leitura**: as três ferramentas têm `readOnlyHint`; não há gravação em nenhum sistema.
- **Contêiner**: sem porta publicada, rede própria `borda-firecrawl` (só o Traefik), só Cloudflare chega (ipallowlist), limite de pedidos no Traefik e 30 leituras/min por pessoa, `read_only`, `cap_drop: ALL`, `no-new-privileges`, 1 GB/1 CPU, usuário sem privilégio.
- **Chrome com sandbox**: precisa do perfil seccomp `seccomp_chrome.json` (cópia do perfil do Playwright, `microsoft/playwright/utils/docker/seccomp_profile.json`, baixado em 21/11/2026, sha256 `cc3e61ca…7849`). Nunca usar `seccomp=unconfined`. Precisa também de `cap_add: [SYS_CHROOT]` (só no conjunto-limite: o processo continua com zero capacidades efetivas; o Chrome usa dentro do próprio user namespace).
- **Registro**: cada uso grava quem, quando, ferramenta e o domínio lido. Nunca o conteúdo.
- O conteúdo devolvido vem marcado como dado de terceiros, nunca instrução.
- Avisos de segurança conhecidos do Firecrawl (RCE/SSRF de 2024-2026) são do servidor completo `apps/api`, que **não** usamos.

## Versões fixas

- Firecrawl Local: commit `e6c2ffdf7072fe9ab72eefa59622454f7480e163` (versão 0.1.1), o mesmo testado na VPS de pré-produção e no notebook em 21/11/2026.
- Rust `1.100.0-slim-trixie` e Python `3.12.15-slim-trixie` por digest; dependências Python em `requirements.txt`.

## Testar

```bash
pip install -r requirements.txt -r requirements-dev.txt
python -m pytest -q
```

## Publicar e instalar

1. Merge na `main`, tag `vX.Y.Z` num commit da main → a Action gera `ghcr.io/oryonntech/firecrawl-mcp:vX.Y.Z`.
2. Na produção, como root: copiar `compose.yaml`, `seccomp_chrome.json`, `env.exemplo` e `producao/*.sh` para `/opt/firecrawl-mcp` e rodar `sudo bash /opt/firecrawl-mcp/instalar.sh`.
3. Cloudflare: registro `mcp-firecrawl.oryonntech.com` com proxy ligado, apontando para a produção.
4. No claude.ai: Configurações > Conectores > Adicionar conector personalizado > `https://mcp-firecrawl.oryonntech.com/mcp`.

Desfazer: `sudo bash /opt/firecrawl-mcp/desfazer.sh`.

## Licença

Este repositório usa o Firecrawl Local sem modificação, compilado do código-fonte oficial (AGPL-3.0). Uso interno; se um dia o serviço for oferecido a terceiros, o código-fonte do Firecrawl (e de qualquer modificação) precisa ficar disponível a eles.

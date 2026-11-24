# MCP "Firecrawl gratuito": Firecrawl Local (AGPL-3.0) + servidor MCP HTTP com login.
# Estágio 1: compila o Firecrawl Local no commit testado em 21/11/2026 (VPS pré-prod e notebook).
FROM rust:1.100.0-slim-trixie@sha256:6f14b2b4b278ec0d50aa1d69541c304ce0f95e0f6268487aa9924af1c2e9aebe AS motor
ARG FIRECRAWL_COMMIT=e6c2ffdf7072fe9ab72eefa59622454f7480e163
RUN apt-get update && apt-get install -y --no-install-recommends git ca-certificates build-essential pkg-config \
 && rm -rf /var/lib/apt/lists/*
WORKDIR /src
RUN git init -q firecrawl && cd firecrawl \
 && git remote add origin https://github.com/firecrawl/firecrawl.git \
 && git fetch -q --depth 1 origin "$FIRECRAWL_COMMIT" && git checkout -q FETCH_HEAD \
 && test "$(git rev-parse HEAD)" = "$FIRECRAWL_COMMIT"
RUN cd firecrawl/apps/local && cargo build --release --locked \
 && cp target/release/firecrawl-local /firecrawl-local

# Estágio 2: só o necessário para rodar.
FROM python:3.12.16-slim@sha256:5e2bdb1b0d542d5039cffb8181c65930093949194a65c365dfb1b0fe13a4fa5b
RUN apt-get update && apt-get install -y --no-install-recommends chromium fonts-liberation ca-certificates \
 && apt-get install -y --no-install-recommends --only-upgrade ca-certificates \
 && rm -rf /var/lib/apt/lists/* \
 && useradd --system --create-home --home-dir /app firecrawl
COPY --from=motor /firecrawl-local /usr/local/bin/firecrawl-local
# Dependências só pelo lock com hash (inclui as indiretas). Fonte: requirements.txt.
COPY requirements.lock /app/requirements.lock
RUN pip install --no-cache-dir --require-hashes --no-deps -r /app/requirements.lock
USER firecrawl
WORKDIR /app
COPY --chown=firecrawl:firecrawl servidor.py /app/
# FIRECRAWL_CLOUD=off: nada vai para a nuvem do Firecrawl (LGPD). O servidor.py força de novo.
ENV MCP_BIND=0.0.0.0 MCP_PORT=8766 PYTHONUNBUFFERED=1 \
    FIRECRAWL_CLOUD=off FIRECRAWL_LOCAL_BROWSER=auto FIRECRAWL_CHROME_PATH=/usr/bin/chromium \
    FIRECRAWL_LOCAL_HOME=/tmp/firecrawl-local HOME=/tmp
EXPOSE 8766
HEALTHCHECK --interval=30s --timeout=5s --start-period=30s --retries=3 \
  CMD ["python3", "-c", "import sys,urllib.request\ntry:\n urllib.request.urlopen('http://127.0.0.1:8766/saude', timeout=4); urllib.request.urlopen('http://127.0.0.1:3002/health', timeout=4)\nexcept Exception:\n sys.exit(1)"]
CMD ["python3", "/app/servidor.py"]

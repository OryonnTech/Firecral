"""Testes do portão de acesso e das travas, sem rede e sem o Firecrawl Local."""
import importlib
import os
import sys

import pytest

os.environ.setdefault("MCP_PUBLIC_HOST", "mcp-firecrawl.exemplo.com")
os.environ.setdefault("MCP_ACCESS_TOKEN", "t" * 40)
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
servidor = importlib.import_module("servidor")

from starlette.testclient import TestClient  # noqa: E402

HOST = {"host": "mcp-firecrawl.exemplo.com"}


@pytest.mark.parametrize(
    "url",
    [
        "http://127.0.0.1:3002/health",
        "http://10.88.0.200:3000",
        "http://192.168.0.1",
        "http://172.17.0.1",
        "http://169.254.169.254/latest/meta-data",
        "http://[::1]/",
        "http://localhost:8080",
        "http://git.preprod.internal",
        "ftp://exemplo.com",
        "file:///etc/passwd",
        "https://usuario:senha@exemplo.com",
        "exemplo.com",
        "",
    ],
)
def test_recusa_endereco_interno_ou_invalido(url):
    with pytest.raises(servidor.ErroDeUso):
        servidor.conferir_url(url)


@pytest.mark.parametrize("url", ["https://www.ecosan.com", "http://8.8.8.8/x", "https://g1.globo.com/a?b=1"])
def test_aceita_site_publico(url):
    assert servidor.conferir_url(url) == url


def test_limite_por_minuto():
    servidor._chamadas.clear()
    for i in range(servidor.LIMITE_POR_MINUTO):
        servidor.conferir_limite("ana", agora=100.0 + i * 0.1)
    with pytest.raises(servidor.ErroDeUso):
        servidor.conferir_limite("ana", agora=105.0)
    servidor.conferir_limite("bia", agora=105.0)  # outra pessoa não é afetada
    servidor.conferir_limite("ana", agora=200.0)  # passou o minuto


def test_corta_texto_grande():
    texto = "x" * (servidor.MAX_CARACTERES + 10)
    saida = servidor.cortar(texto)
    assert saida.startswith("x" * 100) and "cortado" in saida


def test_pagina_traz_aviso_de_dado_e_fonte():
    dados = {"success": True, "data": {"markdown": "# Oi", "metadata": {"sourceURL": "https://a.com", "title": "A"}}}
    saida = servidor.montar_pagina(dados, "markdown")
    assert servidor.AVISO in saida and "Fonte: https://a.com" in saida and "# Oi" in saida


def test_pagina_bloqueada_avisa():
    dados = {"success": True, "data": {"blocked": True, "markdown": "", "metadata": {}}}
    assert "bloqueou" in servidor.montar_pagina(dados, "markdown")


def test_so_ferramentas_de_leitura():
    import asyncio

    ferramentas = asyncio.run(servidor.mcp.list_tools())
    assert sorted(t.name for t in ferramentas) == ["ler_pagina", "ler_site", "listar_paginas"]
    assert all(t.annotations.readOnlyHint and not t.annotations.destructiveHint for t in ferramentas)


def test_sem_token_da_401():
    cliente = TestClient(servidor.app)
    r = cliente.post("/mcp", headers=HOST, json={})
    assert r.status_code == 401


def test_token_errado_da_401():
    cliente = TestClient(servidor.app)
    r = cliente.post("/mcp", headers={**HOST, "authorization": "Bearer " + "x" * 40}, json={})
    assert r.status_code == 401


def test_saude_sem_login():
    cliente = TestClient(servidor.app)
    r = cliente.get("/saude", headers=HOST)
    assert r.status_code == 200 and r.json() == {"ok": True}


def test_motor_sobe_sem_nuvem_e_sem_rede_privada(monkeypatch):
    capturado = {}

    class Falso:
        def poll(self):
            return None

    def popen(cmd, env):
        capturado["cmd"], capturado["env"] = cmd, env
        return Falso()

    class Resp:
        status_code = 200

    monkeypatch.setenv("FIRECRAWL_LOCAL_ALLOW_PRIVATE", "1")
    monkeypatch.setenv("FIRECRAWL_CLOUD", "auto")
    monkeypatch.setattr(servidor.subprocess, "Popen", popen)
    monkeypatch.setattr(servidor.httpx, "get", lambda *a, **k: Resp())
    servidor.subir_motor()
    assert capturado["env"]["FIRECRAWL_CLOUD"] == "off"
    assert "FIRECRAWL_LOCAL_ALLOW_PRIVATE" not in capturado["env"]
    assert "--allow-private" not in capturado["cmd"]
    assert capturado["cmd"][capturado["cmd"].index("--host") + 1] == "127.0.0.1"

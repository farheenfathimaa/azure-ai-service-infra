from fastapi.testclient import TestClient

import main
from config import Settings


def _client(monkeypatch, **env):
    defaults = {
        "LLM_PROVIDER": "echo",
        "ALLOW_BOOM": "true",
    }
    defaults.update(env)
    for key, value in defaults.items():
        monkeypatch.setenv(key, value)
    main.get_settings.cache_clear()
    return TestClient(main.app)


def test_health_ok(monkeypatch):
    with _client(monkeypatch) as client:
        resp = client.get("/health")
    assert resp.status_code == 200
    body = resp.json()
    assert body["status"] == "ok"
    assert body["provider"] == "echo"
    assert body["documents"] >= 1


def test_ask_returns_answer(monkeypatch):
    with _client(monkeypatch) as client:
        resp = client.post("/ask", json={"question": "What is the health endpoint?"})
    assert resp.status_code == 200
    body = resp.json()
    assert body["provider"] == "echo"
    assert "intro" in body["sources"]


def test_boom_returns_500(monkeypatch):
    with _client(monkeypatch) as client:
        resp = client.get("/boom")
    assert resp.status_code == 500


def test_boom_disabled(monkeypatch):
    with _client(monkeypatch, ALLOW_BOOM="false") as client:
        resp = client.get("/boom")
    assert resp.status_code == 404


def test_provider_falls_back_to_groq(monkeypatch):
    settings = Settings(
        llm_provider="azure_openai",
        azure_openai_endpoint=None,
        groq_api_key="test-key",
        allow_fallback=True,
    )
    assert settings.resolve_provider() == "groq"


def test_provider_echo_when_nothing_configured():
    settings = Settings(llm_provider="auto", allow_fallback=True)
    assert settings.resolve_provider() == "echo"

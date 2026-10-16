from __future__ import annotations

import logging

import httpx

from config import Settings

logger = logging.getLogger(__name__)

SYSTEM_PROMPT = (
    "You are a helpful assistant. Answer the user's question using the provided "
    "context when it is relevant. If the context is empty, answer from general "
    "knowledge and say when you are unsure."
)


class LLMClient:
    """Thin chat-completions client with Azure OpenAI primary and Groq fallback."""

    def __init__(self, settings: Settings):
        self.settings = settings
        self._client = httpx.Client(timeout=settings.request_timeout_seconds)

    def complete(self, question: str, context: list[str]) -> dict:
        provider = self.settings.resolve_provider()
        messages = self._build_messages(question, context)
        try:
            content = self._dispatch(provider, messages)
            return {"provider": provider, "answer": content}
        except Exception as exc:  # noqa: BLE001 - fall back on any provider error
            logger.warning("provider %s failed: %s", provider, exc)
            fallback = self._fallback_for(provider)
            if fallback:
                content = self._dispatch(fallback, messages)
                return {"provider": fallback, "answer": content, "fallback_from": provider}
            raise

    def _dispatch(self, provider: str, messages: list[dict]) -> str:
        if provider == "azure_openai":
            return self._call_azure_openai(messages)
        if provider == "groq":
            return self._call_groq(messages)
        return self._echo(messages)

    def _fallback_for(self, provider: str) -> str | None:
        if not self.settings.allow_fallback:
            return None
        if provider == "azure_openai" and self.settings.groq_configured:
            return "groq"
        if provider == "groq" and self.settings.azure_openai_configured:
            return "azure_openai"
        return None

    def _build_messages(self, question: str, context: list[str]) -> list[dict]:
        if context:
            joined = "\n\n".join(f"[{i + 1}] {c}" for i, c in enumerate(context))
            user = f"Context:\n{joined}\n\nQuestion: {question}"
        else:
            user = question
        return [
            {"role": "system", "content": SYSTEM_PROMPT},
            {"role": "user", "content": user},
        ]

    def _call_azure_openai(self, messages: list[dict]) -> str:
        url = (
            f"{self.settings.azure_openai_endpoint.rstrip('/')}/openai/deployments/"
            f"{self.settings.azure_openai_deployment}/chat/completions"
        )
        resp = self._client.post(
            url,
            params={"api-version": self.settings.azure_openai_api_version},
            headers={"api-key": self.settings.azure_openai_key or ""},
            json={"messages": messages, "temperature": 0.2},
        )
        resp.raise_for_status()
        return resp.json()["choices"][0]["message"]["content"]

    def _call_groq(self, messages: list[dict]) -> str:
        resp = self._client.post(
            f"{self.settings.groq_base_url.rstrip('/')}/chat/completions",
            headers={
                "Authorization": f"Bearer {self.settings.groq_api_key}",
                "Content-Type": "application/json",
            },
            json={"model": self.settings.groq_model, "messages": messages, "temperature": 0.2},
        )
        resp.raise_for_status()
        return resp.json()["choices"][0]["message"]["content"]

    def _echo(self, messages: list[dict]) -> str:
        question = messages[-1]["content"]
        return (
            "No LLM provider is configured, so this is an echo response. "
            f"Received: {question}"
        )

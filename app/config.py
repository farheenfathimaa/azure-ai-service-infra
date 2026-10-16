from __future__ import annotations

from functools import lru_cache
from typing import Literal

from pydantic_settings import BaseSettings, SettingsConfigDict

Provider = Literal["auto", "azure_openai", "groq", "echo"]


class Settings(BaseSettings):
    """Runtime configuration, populated from environment variables.

    Secrets (API keys) are injected by Azure Container Apps from Key Vault at
    runtime, so they never live in the image or in source control.
    """

    model_config = SettingsConfigDict(env_file=".env", env_file_encoding="utf-8", extra="ignore")

    app_name: str = "azure-ai-service"
    app_env: str = "dev"
    log_level: str = "INFO"

    # Provider toggle: "auto" prefers Azure OpenAI, then falls back to Groq.
    llm_provider: Provider = "auto"
    allow_fallback: bool = True

    # Azure OpenAI (optional at deploy time, enabled by a Terraform toggle)
    azure_openai_endpoint: str | None = None
    azure_openai_key: str | None = None
    azure_openai_deployment: str | None = None
    azure_openai_api_version: str = "2024-10-21"

    # Groq fallback
    groq_api_key: str | None = None
    groq_base_url: str = "https://api.groq.com/openai/v1"
    groq_model: str = "llama-3.1-8b-instant"

    request_timeout_seconds: float = 30.0
    rag_top_k: int = 3

    # Exposes a /boom endpoint used to exercise the 5xx alert. Disable in prod.
    allow_boom: bool = True

    @property
    def azure_openai_configured(self) -> bool:
        return bool(
            self.azure_openai_endpoint
            and self.azure_openai_key
            and self.azure_openai_deployment
        )

    @property
    def groq_configured(self) -> bool:
        return bool(self.groq_api_key)

    def resolve_provider(self) -> Provider:
        if self.llm_provider != "auto":
            chosen = self.llm_provider
        elif self.azure_openai_configured:
            chosen = "azure_openai"
        elif self.groq_configured:
            chosen = "groq"
        else:
            chosen = "echo"

        if chosen == "azure_openai" and not self.azure_openai_configured:
            if self.allow_fallback and self.groq_configured:
                return "groq"
            return "echo"
        if chosen == "groq" and not self.groq_configured:
            if self.allow_fallback and self.azure_openai_configured:
                return "azure_openai"
            return "echo"
        return chosen


@lru_cache
def get_settings() -> Settings:
    return Settings()

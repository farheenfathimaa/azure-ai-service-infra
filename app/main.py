from __future__ import annotations

import logging
from contextlib import asynccontextmanager

from fastapi import FastAPI, HTTPException, Request
from fastapi.responses import JSONResponse
from pydantic import BaseModel, Field

from config import get_settings
from llm import LLMClient
from rag import RagStore

logging.basicConfig(level=get_settings().log_level)
logger = logging.getLogger(__name__)

SEED_DOCS = {
    "intro": (
        "This service is a FastAPI application deployed on Azure Container Apps. "
        "It exposes a RAG endpoint at /ask and a health endpoint at /health."
    ),
    "fallback": (
        "The LLM provider defaults to Azure OpenAI. When Azure OpenAI is disabled or "
        "errors, the service falls back to Groq if a Groq API key is configured."
    ),
    "secrets": (
        "API keys are stored in Azure Key Vault and injected into the container at "
        "runtime through the user-assigned managed identity. No secrets are stored in "
        "source control or in the container image."
    ),
}


@asynccontextmanager
async def lifespan(app: FastAPI):
    settings = get_settings()
    store = RagStore(top_k=settings.rag_top_k)
    for doc_id, text in SEED_DOCS.items():
        store.ingest(doc_id, text)
    app.state.settings = settings
    app.state.store = store
    app.state.llm = LLMClient(settings)
    logger.info("startup complete provider=%s", settings.resolve_provider())
    yield
    app.state.llm._client.close()


app = FastAPI(title="Azure AI Service", version="1.0.0", lifespan=lifespan)


class AskRequest(BaseModel):
    question: str = Field(min_length=1, max_length=4000)
    top_k: int | None = Field(default=None, ge=1, le=10)


class AskResponse(BaseModel):
    answer: str
    provider: str
    fallback_from: str | None = None
    sources: list[str]


class HealthResponse(BaseModel):
    status: str
    app: str
    environment: str
    provider: str
    documents: int


@app.get("/health", response_model=HealthResponse)
def health(request: Request) -> HealthResponse:
    settings = request.app.state.settings
    return HealthResponse(
        status="ok",
        app=settings.app_name,
        environment=settings.app_env,
        provider=settings.resolve_provider(),
        documents=request.app.state.store.count(),
    )


@app.post("/ask", response_model=AskResponse)
def ask(payload: AskRequest, request: Request) -> AskResponse:
    store: RagStore = request.app.state.store
    docs = store.retrieve(payload.question, payload.top_k)
    context = [d.text for d in docs]
    try:
        result = request.app.state.llm.complete(payload.question, context)
    except Exception as exc:  # noqa: BLE001
        logger.exception("llm request failed")
        raise HTTPException(status_code=502, detail="LLM provider unavailable") from exc
    return AskResponse(
        answer=result["answer"],
        provider=result["provider"],
        fallback_from=result.get("fallback_from"),
        sources=[d.id for d in docs],
    )


@app.get("/boom")
def boom(request: Request) -> JSONResponse:
    if not request.app.state.settings.allow_boom:
        raise HTTPException(status_code=404, detail="not found")
    logger.error("intentional failure for alert testing")
    raise HTTPException(status_code=500, detail="intentional server error")


@app.exception_handler(Exception)
async def unhandled_exception_handler(request: Request, exc: Exception) -> JSONResponse:
    logger.exception("unhandled error on %s", request.url.path)
    return JSONResponse(status_code=500, content={"detail": "internal server error"})

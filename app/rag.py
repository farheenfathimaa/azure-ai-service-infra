from __future__ import annotations

import re
from dataclasses import dataclass, field

_TOKEN_RE = re.compile(r"[a-z0-9]+")

_STOPWORDS = {
    "the", "a", "an", "and", "or", "of", "to", "in", "is", "are", "for", "on",
    "with", "as", "at", "by", "be", "it", "that", "this", "what", "how",
}


def _tokenize(text: str) -> set[str]:
    return {t for t in _TOKEN_RE.findall(text.lower()) if t not in _STOPWORDS}


@dataclass
class Document:
    id: str
    text: str
    metadata: dict = field(default_factory=dict)
    _tokens: set[str] = field(default_factory=set, repr=False)

    def __post_init__(self) -> None:
        self._tokens = _tokenize(self.text)


class RagStore:
    """Minimal in-memory retriever using keyword-overlap scoring.

    Deliberately dependency-free so the service boots fast and cheaply. Swap in a
    vector store (Azure AI Search, pgvector, ...) behind `retrieve` when needed.
    """

    def __init__(self, top_k: int = 3):
        self.top_k = top_k
        self._docs: dict[str, Document] = {}

    def ingest(self, doc_id: str, text: str, metadata: dict | None = None) -> Document:
        doc = Document(id=doc_id, text=text, metadata=metadata or {})
        self._docs[doc_id] = doc
        return doc

    def delete(self, doc_id: str) -> bool:
        return self._docs.pop(doc_id, None) is not None

    def count(self) -> int:
        return len(self._docs)

    def retrieve(self, query: str, top_k: int | None = None) -> list[Document]:
        k = top_k or self.top_k
        q_tokens = _tokenize(query)
        if not q_tokens:
            return []
        scored: list[tuple[float, Document]] = []
        for doc in self._docs.values():
            overlap = q_tokens & doc._tokens
            if not overlap:
                continue
            score = len(overlap) / len(q_tokens)
            scored.append((score, doc))
        scored.sort(key=lambda item: item[0], reverse=True)
        return [doc for _, doc in scored[:k]]

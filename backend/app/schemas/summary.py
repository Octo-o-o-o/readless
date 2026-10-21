"""Pydantic models for AI-generated summaries."""

import hashlib

from pydantic import BaseModel


class OutlinePoint(BaseModel):
    """A single outline point with source-paragraph anchors."""

    id: str | None = None
    point: str
    anchors: list[str]
    detail: str | None = None


def make_outline_point_id(
    *,
    index: int,
    point: str,
    anchors: list[str],
    content_id: str | None = None,
) -> str:
    """Build a deterministic outline ID for stable client-side diffing."""
    normalized_anchors = "|".join(sorted(anchor.strip() for anchor in anchors))
    stable_input = "\n".join(
        [
            content_id or "",
            str(index),
            point.strip(),
            normalized_anchors,
        ]
    )
    return hashlib.sha1(stable_input.encode("utf-8")).hexdigest()[:16]


def stabilize_outline_points(
    outline: list[OutlinePoint | dict],
    *,
    content_id: str | None = None,
) -> list[OutlinePoint]:
    """Ensure every outline point carries a deterministic ID."""
    stabilized: list[OutlinePoint] = []
    for index, item in enumerate(outline):
        point = item if isinstance(item, OutlinePoint) else OutlinePoint(**item)
        if point.id:
            stabilized.append(point)
            continue
        stabilized.append(
            point.model_copy(
                update={
                    "id": make_outline_point_id(
                        index=index,
                        point=point.point,
                        anchors=point.anchors,
                        content_id=content_id,
                    )
                }
            )
        )
    return stabilized


class ContentSummary(BaseModel):
    """Multi-level summary produced by the AI summarization service."""

    l0_summary: str
    l1_outline: list[OutlinePoint]
    tags: list[str]
    keywords: list[str]
    language_code: str | None = None

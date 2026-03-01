"""Content processing pipeline: extract -> summarize -> store."""

import uuid

from sqlalchemy import text
from sqlalchemy.ext.asyncio import AsyncSession

from app.models.content import Content
from app.models.paragraph import Paragraph
from app.services.extractor import ContentExtractor
from app.services.summarizer import SummarizationService


class ProcessingPipeline:
    """Orchestrates content extraction, AI summarization, and storage."""

    def __init__(self) -> None:
        self.extractor = ContentExtractor()
        self._summarizer: SummarizationService | None = None

    @property
    def summarizer(self) -> SummarizationService:
        """Lazily create the summarization service on first access."""
        if self._summarizer is None:
            self._summarizer = SummarizationService()
        return self._summarizer

    async def process(
        self,
        source_type: str,
        body: str,
        user_id: str,
        source_app_name: str | None = None,
        source_app_bundle_id: str | None = None,
        channel: str = "manual",
        *,
        db: AsyncSession,
    ) -> Content:
        """Run the full extract -> summarize -> store pipeline."""
        content_id = str(uuid.uuid4())

        # Step 1: Extract content
        if source_type == "url":
            extracted = await self.extractor.extract_url(body)
        elif source_type == "text":
            extracted = await self.extractor.extract_text(body)
        elif source_type == "pdf":
            extracted = await self.extractor.extract_pdf(body)
        elif source_type == "image":
            extracted = await self.extractor.extract_image(body)
        else:
            raise ValueError(f"Unsupported source_type: {source_type}")

        # Step 2: AI Summarize
        summary, detected_language = await self.summarizer.summarize(extracted)

        # Step 3: Store in DB
        content = Content(
            id=content_id,
            title=extracted.title,
            source_url=extracted.source_url,
            source_type=source_type,
            source_app_name=source_app_name,
            source_app_bundle_id=source_app_bundle_id,
            channel=channel,
            source_language=detected_language,
            l0_summary=summary.l0_summary,
            l1_outline=[p.model_dump() for p in summary.l1_outline],
            tags=summary.tags,
            keywords=summary.keywords,
            full_text=extracted.full_text,
            status="ready",
            user_id=user_id,
        )
        db.add(content)

        # Step 4: Store paragraphs
        for para in extracted.paragraphs:
            db.add(
                Paragraph(
                    content_id=content_id,
                    anchor_id=para.anchor_id,
                    text=para.text,
                    position=para.position,
                )
            )

        # Step 5: Flush to get rows into the DB (within same transaction)
        await db.flush()

        # Step 6: Update full-text search vectors (same transaction as insert)
        await db.execute(
            text("""
            UPDATE contents SET full_text_tsv =
                setweight(to_tsvector('simple', coalesce(title,'')), 'A') ||
                setweight(to_tsvector('simple', coalesce(l0_summary,'')), 'A') ||
                setweight(to_tsvector('simple', coalesce(full_text,'')), 'C')
            WHERE id = :id
        """),
            {"id": content_id},
        )

        await db.execute(
            text("""
            UPDATE paragraphs SET full_text_tsv = to_tsvector('simple', text)
            WHERE content_id = :id
        """),
            {"id": content_id},
        )

        # Single atomic commit: rows + FTS vectors
        await db.commit()
        return content

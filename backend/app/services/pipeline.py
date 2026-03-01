"""Content processing pipeline: extract -> summarize -> store."""

import logging
import uuid

from sqlalchemy import select, text
from sqlalchemy.ext.asyncio import AsyncSession

from app.models.content import Content
from app.models.content_tag import ContentTag
from app.models.paragraph import Paragraph
from app.models.user_tag import UserTag
from app.services.extractor import ContentExtractor
from app.services.summarizer import SummarizationService

logger = logging.getLogger(__name__)


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

        # Step 2: AI Summarize with tag selection
        # Extract paragraphs as text list for the new generate_summary API
        paragraph_texts = [p.text for p in extracted.paragraphs]

        summary = await self.summarizer.generate_summary(
            full_text=extracted.full_text,
            paragraphs=paragraph_texts,
            user_id=user_id,
            db=db,
        )

        # Detect language from L0 summary
        from app.services.translator import _get_service
        translator = _get_service()
        detected_language = await translator.detect_language(summary.l0_summary)

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
            keywords=summary.keywords,
            full_text=extracted.full_text,
            status="ready",
            user_id=user_id,
        )
        db.add(content)

        # Step 3a: Save tags to content_tags table
        if summary.tags:
            # Batch lookup all tags at once to avoid N+1 queries
            stmt = select(UserTag.id, UserTag.tag_name).where(
                UserTag.user_id == user_id,
                UserTag.tag_name.in_(summary.tags),
                UserTag.deleted_at.is_(None),
            )
            result = await db.execute(stmt)
            tag_map = {row.tag_name: row.id for row in result}

            # Create relationships for found tags
            for tag_name in summary.tags:
                if tag_id := tag_map.get(tag_name):
                    content_tag = ContentTag(
                        content_id=content_id,
                        tag_id=tag_id,
                        user_id=user_id,
                    )
                    db.add(content_tag)
                else:
                    logger.warning(
                        f"AI selected tag '{tag_name}' not found in user {user_id}'s library for content {content_id}"
                    )

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

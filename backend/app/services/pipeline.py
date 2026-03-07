"""Content processing pipeline: extract -> summarize -> store."""

import logging
import math
import uuid

from sqlalchemy import select, text
from sqlalchemy.ext.asyncio import AsyncSession

from app.models.content import Content
from app.models.content_tag import ContentTag
from app.models.paragraph import Paragraph
from app.models.user_tag import UserTag
from app.schemas.summary import ContentSummary
from app.services.extractor import ContentExtractor
from app.services.summarizer import SummarizationService

logger = logging.getLogger(__name__)

# ------------------------------------------------------------------ #
#  Content length thresholds for tiered summarization
# ------------------------------------------------------------------ #
MIN_CONTENT_LENGTH = 100        # Below: just store, no AI summarization
MIN_LENGTH_FOR_OUTLINE = 500    # Below: L0 only; above: L0 + L1 outline
CHARS_PER_OUTLINE_POINT = 500   # One outline point per N chars of content
MAX_OUTLINE_POINTS = 7          # Upper cap on outline points


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

        # Step 2: Tiered summarization based on content length
        content_length = len(extracted.full_text)
        paragraph_texts = [p.text for p in extracted.paragraphs]

        if content_length < MIN_CONTENT_LENGTH:
            # Very short content: just store, no AI processing
            logger.info(
                "Content too short (%d chars < %d), skipping AI summarization",
                content_length, MIN_CONTENT_LENGTH,
            )
            summary = ContentSummary(
                l0_summary=extracted.full_text,
                l1_outline=[],
                tags=[],
                keywords=[],
            )
            has_chinese = any("\u4e00" <= c <= "\u9fff" for c in extracted.full_text[:200])
            detected_language = "zh" if has_chinese else "en"
        else:
            # Determine outline point count: 0 for short, dynamic for long
            if content_length < MIN_LENGTH_FOR_OUTLINE:
                max_points = 0
                logger.info(
                    "Short content (%d chars < %d), generating L0 only",
                    content_length, MIN_LENGTH_FOR_OUTLINE,
                )
            else:
                max_points = min(
                    math.ceil(content_length / CHARS_PER_OUTLINE_POINT),
                    MAX_OUTLINE_POINTS,
                )
                logger.info(
                    "Content %d chars → up to %d outline points",
                    content_length, max_points,
                )

            summary = await self.summarizer.generate_summary(
                full_text=extracted.full_text,
                paragraphs=paragraph_texts,
                user_id=user_id,
                db=db,
                max_outline_points=max_points,
            )

            # Detect language from L0 summary
            from app.services.translator import _get_service
            translator = _get_service()
            detected_language = await translator.detect_language(summary.l0_summary)

            # Pre-generate L2 details (only if outline exists)
            if summary.l1_outline:
                summary.l1_outline = await self.summarizer.pre_generate_details(
                    extracted, summary.l1_outline
                )

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
                        "AI selected tag '%s' not found in"
                        " user %s's library for content %s",
                        tag_name, user_id, content_id,
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

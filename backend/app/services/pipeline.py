"""Content processing pipeline: extract -> summarize -> store."""

import logging
import math
import uuid
from datetime import UTC, datetime

from sqlalchemy import delete, select, text
from sqlalchemy.ext.asyncio import AsyncSession

from app.models.content import Content
from app.models.content_tag import ContentTag
from app.models.paragraph import Paragraph
from app.models.user_tag import UserTag
from app.schemas.summary import ContentSummary
from app.services.extractor import ContentExtractor, ExtractedContent
from app.services.summarizer import SummarizationService

logger = logging.getLogger(__name__)

# ------------------------------------------------------------------ #
#  Content length thresholds for tiered summarization
# ------------------------------------------------------------------ #
MIN_CONTENT_LENGTH = 100       # Below: just store, no AI summarization
MIN_LENGTH_FOR_OUTLINE = 500   # Below: L0 only; above: L0 + L1 outline
CHARS_PER_OUTLINE_POINT = 500  # One outline point per N chars of content
MAX_OUTLINE_POINTS = 7         # Upper cap on outline points
FAILED_IMPORT_SUMMARY = "Import failed. Please try again."
MAX_PROCESSING_ERROR_CHARS = 500


def truncate_processing_error(message: str | None) -> str | None:
    """Normalize and bound stored processing error text."""
    if message is None:
        return None

    normalized = " ".join(message.split())
    if not normalized:
        return None
    return normalized[:MAX_PROCESSING_ERROR_CHARS]


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

    async def create_pending_content(
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
        """Create a placeholder content row that can be processed in background."""
        content = Content(
            id=str(uuid.uuid4()),
            title=self._build_placeholder_title(source_type, body),
            source_url=body if source_type == "url" else None,
            source_type=source_type,
            source_app_name=source_app_name,
            source_app_bundle_id=source_app_bundle_id,
            channel=channel,
            l0_summary=None,
            l1_outline=None,
            keywords=None,
            full_text=body if source_type == "text" else None,
            status="pending",
            processing_started_at=None,
            processing_finished_at=None,
            processing_error=None,
            processing_attempts=0,
            user_id=user_id,
        )
        db.add(content)
        await db.flush()
        return content

    async def process_pending_content(
        self,
        *,
        content_id: str,
        source_type: str,
        body: str,
        user_id: str,
        db: AsyncSession,
    ) -> Content | None:
        """Process an existing pending content row into a ready or failed item."""
        content = await db.get(Content, content_id)
        if content is None or content.user_id != user_id:
            logger.warning(
                "Skipping content job for missing or foreign content: %s",
                content_id,
            )
            return None

        self._mark_content_processing(content)
        await db.commit()
        await db.refresh(content)

        try:
            await self._process_into_content(
                content=content,
                source_type=source_type,
                body=body,
                user_id=user_id,
                db=db,
            )
            await db.commit()
            await db.refresh(content)
            return content
        except Exception as exc:
            logger.exception("Content processing failed for %s", content_id)
            await db.rollback()

            failed_content = await db.get(Content, content_id)
            if failed_content is None:
                return None

            self._mark_content_failed(failed_content, error=exc)
            await db.commit()
            await db.refresh(failed_content)
            return failed_content

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
        """Run the full extract -> summarize -> store pipeline synchronously."""
        content = Content(
            id=str(uuid.uuid4()),
            title=self._build_placeholder_title(source_type, body),
            source_url=body if source_type == "url" else None,
            source_type=source_type,
            source_app_name=source_app_name,
            source_app_bundle_id=source_app_bundle_id,
            channel=channel,
            status="pending",
            processing_started_at=None,
            processing_finished_at=None,
            processing_error=None,
            processing_attempts=0,
            user_id=user_id,
        )
        db.add(content)
        await db.flush()

        try:
            self._mark_content_processing(content)
            await self._process_into_content(
                content=content,
                source_type=source_type,
                body=body,
                user_id=user_id,
                db=db,
            )
            await db.commit()
            await db.refresh(content)
            return content
        except Exception:
            await db.rollback()
            raise

    async def _process_into_content(
        self,
        *,
        content: Content,
        source_type: str,
        body: str,
        user_id: str,
        db: AsyncSession,
    ) -> None:
        extracted = await self._extract_content(source_type=source_type, body=body)
        summary, detected_language = await self._summarize_content(
            extracted=extracted,
            user_id=user_id,
            db=db,
        )

        content.title = extracted.title
        content.source_url = extracted.source_url
        content.source_language = detected_language
        content.l0_summary = summary.l0_summary
        content.l1_outline = [p.model_dump() for p in summary.l1_outline]
        content.keywords = summary.keywords
        content.full_text = extracted.full_text
        self._mark_content_ready(content)

        await self._replace_related_rows(
            content=content,
            extracted=extracted,
            tags=summary.tags,
            user_id=user_id,
            db=db,
        )

        await db.flush()
        await self._update_full_text_search(content_id=content.id, db=db)

    async def _extract_content(
        self,
        *,
        source_type: str,
        body: str,
    ) -> ExtractedContent:
        if source_type == "url":
            return await self.extractor.extract_url(body)
        if source_type == "text":
            return await self.extractor.extract_text(body)
        if source_type == "pdf":
            return await self.extractor.extract_pdf(body)
        if source_type == "image":
            return await self.extractor.extract_image(body)
        raise ValueError(f"Unsupported source_type: {source_type}")

    async def _summarize_content(
        self,
        *,
        extracted: ExtractedContent,
        user_id: str,
        db: AsyncSession,
    ) -> tuple[ContentSummary, str]:
        content_length = len(extracted.full_text)
        paragraph_texts = [p.text for p in extracted.paragraphs]

        if content_length < MIN_CONTENT_LENGTH:
            logger.info(
                "Content too short (%d chars < %d), skipping AI summarization",
                content_length,
                MIN_CONTENT_LENGTH,
            )
            summary = ContentSummary(
                l0_summary=extracted.full_text,
                l1_outline=[],
                tags=[],
                keywords=[],
            )
            has_chinese = any(
                "\u4e00" <= c <= "\u9fff" for c in extracted.full_text[:200]
            )
            detected_language = "zh" if has_chinese else "en"
            return summary, detected_language

        if content_length < MIN_LENGTH_FOR_OUTLINE:
            max_points = 0
            logger.info(
                "Short content (%d chars < %d), generating L0 only",
                content_length,
                MIN_LENGTH_FOR_OUTLINE,
            )
        else:
            max_points = min(
                math.ceil(content_length / CHARS_PER_OUTLINE_POINT),
                MAX_OUTLINE_POINTS,
            )
            logger.info(
                "Content %d chars -> up to %d outline points",
                content_length,
                max_points,
            )

        summary = await self.summarizer.generate_summary(
            full_text=extracted.full_text,
            paragraphs=paragraph_texts,
            user_id=user_id,
            db=db,
            max_outline_points=max_points,
        )

        from app.services.translator import _get_service

        translator = _get_service()
        detected_language = await translator.detect_language(summary.l0_summary)
        return summary, detected_language

    async def _replace_related_rows(
        self,
        *,
        content: Content,
        extracted: ExtractedContent,
        tags: list[str],
        user_id: str,
        db: AsyncSession,
    ) -> None:
        await db.execute(
            delete(ContentTag).where(ContentTag.content_id == content.id)
        )
        await db.execute(
            delete(Paragraph).where(Paragraph.content_id == content.id)
        )

        if tags:
            stmt = select(UserTag.id, UserTag.tag_name).where(
                UserTag.user_id == user_id,
                UserTag.tag_name.in_(tags),
                UserTag.deleted_at.is_(None),
            )
            result = await db.execute(stmt)
            tag_map = {row.tag_name: row.id for row in result}

            for tag_name in tags:
                if tag_id := tag_map.get(tag_name):
                    db.add(
                        ContentTag(
                            content_id=content.id,
                            tag_id=tag_id,
                            user_id=user_id,
                        )
                    )
                else:
                    logger.warning(
                        "AI selected tag '%s' not found in user %s's library "
                        "for content %s",
                        tag_name,
                        user_id,
                        content.id,
                    )

        for para in extracted.paragraphs:
            db.add(
                Paragraph(
                    content_id=content.id,
                    anchor_id=para.anchor_id,
                    text=para.text,
                    position=para.position,
                )
            )

    async def _update_full_text_search(
        self,
        *,
        content_id: str,
        db: AsyncSession,
    ) -> None:
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

    def _build_placeholder_title(self, source_type: str, body: str) -> str:
        if source_type == "url":
            return body[:160]

        if source_type == "text":
            normalized = " ".join(body.split())
            if normalized:
                return normalized[:80]
            return "Text import"

        if source_type == "pdf":
            return "Importing PDF..."

        if source_type == "image":
            return "Importing image..."

        return "Importing content..."

    def _mark_content_processing(self, content: Content) -> None:
        content.status = "processing"
        content.processing_started_at = datetime.now(UTC)
        content.processing_finished_at = None
        content.processing_error = None
        content.processing_attempts = (content.processing_attempts or 0) + 1

    def _mark_content_ready(self, content: Content) -> None:
        content.status = "ready"
        content.processing_finished_at = datetime.now(UTC)
        content.processing_error = None

    def _mark_content_failed(
        self,
        content: Content,
        *,
        error: Exception | str | None = None,
    ) -> None:
        content.status = "failed"
        content.l0_summary = FAILED_IMPORT_SUMMARY
        content.l1_outline = []
        content.keywords = None
        content.processing_finished_at = datetime.now(UTC)

        if isinstance(error, Exception):
            detail = str(error)
            prefix = type(error).__name__
            message = f"{prefix}: {detail}" if detail else prefix
        else:
            message = error

        content.processing_error = truncate_processing_error(message)

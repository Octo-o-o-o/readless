"""Tests for the content processing pipeline, schemas, and router registration.

These tests require NO database, NO API keys, and NO network access.
They verify schema validation, structural correctness, and route registration.
"""

from datetime import datetime
from unittest.mock import AsyncMock, MagicMock, patch
from uuid import uuid4

import pytest
from sqlalchemy import select

from app.schemas.content import (
    ContentCreateRequest,
    ContentResponse,
    ExpandRequest,
    FollowUpRequest,
    TextResponse,
)

# ------------------------------------------------------------------ #
#  ContentCreateRequest schema
# ------------------------------------------------------------------ #


class TestContentCreateRequest:
    """Verify ContentCreateRequest pydantic model validates correctly."""

    def test_valid_url_request(self) -> None:
        req = ContentCreateRequest(
            source_type="url",
            body="https://example.com/article",
        )
        assert req.source_type == "url"
        assert req.body == "https://example.com/article"
        assert req.channel == "manual"
        assert req.source_app_name is None
        assert req.source_app_bundle_id is None

    def test_valid_text_request(self) -> None:
        req = ContentCreateRequest(
            source_type="text",
            body="Some long article text here.",
            source_app_name="Safari",
            source_app_bundle_id="com.apple.Safari",
            channel="share_extension",
        )
        assert req.source_type == "text"
        assert req.source_app_name == "Safari"
        assert req.source_app_bundle_id == "com.apple.Safari"
        assert req.channel == "share_extension"

    def test_default_channel(self) -> None:
        req = ContentCreateRequest(source_type="pdf", body="base64data")
        assert req.channel == "manual"

    def test_missing_required_field(self) -> None:
        with pytest.raises(Exception):
            ContentCreateRequest(source_type="url")  # type: ignore[call-arg]

    def test_serialization(self) -> None:
        req = ContentCreateRequest(
            source_type="image",
            body="base64imagedata",
            source_app_name="Photos",
        )
        data = req.model_dump()
        assert data["source_type"] == "image"
        assert data["body"] == "base64imagedata"
        assert data["source_app_name"] == "Photos"
        assert data["source_app_bundle_id"] is None

    def test_from_dict(self) -> None:
        data = {"source_type": "url", "body": "https://example.com"}
        req = ContentCreateRequest(**data)
        assert req.source_type == "url"

    def test_json_roundtrip(self) -> None:
        original = ContentCreateRequest(
            source_type="text",
            body="Hello world",
            channel="api",
        )
        json_str = original.model_dump_json()
        restored = ContentCreateRequest.model_validate_json(json_str)
        assert restored == original

    def test_rejects_oversized_text_body(self) -> None:
        with pytest.raises(ValueError, match="Text import is too large"):
            ContentCreateRequest(
                source_type="text",
                body="x" * 200_001,
            )

    def test_rejects_oversized_upload_body(self) -> None:
        with pytest.raises(ValueError, match="Uploaded file is too large"):
            ContentCreateRequest(
                source_type="pdf",
                body="a" * 14_000_000,
            )


# ------------------------------------------------------------------ #
#  ContentResponse schema
# ------------------------------------------------------------------ #


class TestContentResponse:
    """Verify ContentResponse pydantic model validates correctly."""

    def test_valid_response(self) -> None:
        resp = ContentResponse(
            id="abc-123",
            title="Test Article",
            source_url="https://example.com",
            source_type="url",
            source_app_name=None,
            l0_summary="A short summary.",
            l1_outline=[
                {"point": "First point", "anchors": ["¶1"]},
            ],
            tags=["tech", "ai"],
            status="ready",
            created_at=datetime(2025, 1, 1),
        )
        assert resp.id == "abc-123"
        assert resp.title == "Test Article"
        assert resp.status == "ready"
        assert resp.podcast_url is None

    def test_nullable_fields(self) -> None:
        resp = ContentResponse(
            id="xyz",
            title="Title",
            source_url=None,
            source_type="text",
            source_app_name=None,
            l0_summary=None,
            l1_outline=None,
            tags=None,
            status="pending",
            created_at=datetime(2025, 6, 15),
        )
        assert resp.source_url is None
        assert resp.l0_summary is None
        assert resp.l1_outline is None
        assert resp.tags is None

    def test_with_podcast_url(self) -> None:
        resp = ContentResponse(
            id="pod-1",
            title="Podcast Article",
            source_url=None,
            source_type="url",
            source_app_name=None,
            l0_summary="Summary",
            l1_outline=[],
            tags=[],
            status="ready",
            created_at=datetime(2025, 3, 1),
            podcast_url="https://cdn.example.com/audio.mp3",
        )
        assert resp.podcast_url == "https://cdn.example.com/audio.mp3"

    def test_missing_required_field(self) -> None:
        with pytest.raises(Exception):
            ContentResponse(
                id="abc",
                title="Title",
                # missing source_url, source_type, etc.
            )  # type: ignore[call-arg]

    def test_serialization(self) -> None:
        resp = ContentResponse(
            id="ser-1",
            title="Serialization Test",
            source_url=None,
            source_type="text",
            source_app_name="Notes",
            l0_summary="Summary",
            l1_outline=[{"point": "A", "anchors": ["¶1"]}],
            tags=["test"],
            status="ready",
            created_at=datetime(2025, 5, 20, 12, 0, 0),
        )
        data = resp.model_dump()
        assert data["id"] == "ser-1"
        assert data["source_app_name"] == "Notes"
        assert len(data["l1_outline"]) == 1


# ------------------------------------------------------------------ #
#  ExpandRequest schema
# ------------------------------------------------------------------ #


class TestExpandRequest:
    """Verify ExpandRequest pydantic model validates correctly."""

    def test_valid_request(self) -> None:
        req = ExpandRequest(point_index=0)
        assert req.point_index == 0

    def test_larger_index(self) -> None:
        req = ExpandRequest(point_index=4)
        assert req.point_index == 4

    def test_missing_field(self) -> None:
        with pytest.raises(Exception):
            ExpandRequest()  # type: ignore[call-arg]

    def test_serialization(self) -> None:
        req = ExpandRequest(point_index=2)
        data = req.model_dump()
        assert data == {"point_index": 2}


# ------------------------------------------------------------------ #
#  FollowUpRequest schema
# ------------------------------------------------------------------ #


class TestFollowUpRequest:
    """Verify FollowUpRequest pydantic model validates correctly."""

    def test_valid_request(self) -> None:
        req = FollowUpRequest(question="What is the main argument?")
        assert req.question == "What is the main argument?"

    def test_missing_field(self) -> None:
        with pytest.raises(Exception):
            FollowUpRequest()  # type: ignore[call-arg]

    def test_serialization(self) -> None:
        req = FollowUpRequest(question="How does this relate to X?")
        data = req.model_dump()
        assert data == {"question": "How does this relate to X?"}

    def test_json_roundtrip(self) -> None:
        original = FollowUpRequest(question="Test question?")
        json_str = original.model_dump_json()
        restored = FollowUpRequest.model_validate_json(json_str)
        assert restored == original


# ------------------------------------------------------------------ #
#  TextResponse schema
# ------------------------------------------------------------------ #


class TestTextResponse:
    """Verify TextResponse pydantic model validates correctly."""

    def test_valid_response(self) -> None:
        resp = TextResponse(text="Detailed explanation of the point.")
        assert resp.text == "Detailed explanation of the point."

    def test_empty_text(self) -> None:
        resp = TextResponse(text="")
        assert resp.text == ""

    def test_missing_field(self) -> None:
        with pytest.raises(Exception):
            TextResponse()  # type: ignore[call-arg]

    def test_serialization(self) -> None:
        resp = TextResponse(text="Answer text")
        data = resp.model_dump()
        assert data == {"text": "Answer text"}


# ------------------------------------------------------------------ #
#  Pipeline structural tests
# ------------------------------------------------------------------ #


class TestPipelineStructure:
    """Verify ProcessingPipeline class structure without calling external services."""

    def test_pipeline_importable(self) -> None:
        from app.services.pipeline import ProcessingPipeline

        assert ProcessingPipeline is not None

    def test_pipeline_has_process_method(self) -> None:
        from app.services.pipeline import ProcessingPipeline

        assert hasattr(ProcessingPipeline, "process")
        assert callable(getattr(ProcessingPipeline, "process"))

    def test_pipeline_has_extractor_and_summarizer(self) -> None:
        from app.services.pipeline import ProcessingPipeline

        p = ProcessingPipeline()
        assert hasattr(p, "extractor")
        # summarizer is a lazy property — verify it's defined on the class
        assert "summarizer" in dir(p)


@pytest.mark.asyncio
async def test_create_content_route_returns_pending_and_schedules_background_job():
    """POST route should return pending content and enqueue background work."""
    from app.models.content import Content
    from app.routers.content import create_content

    req = ContentCreateRequest(source_type="text", body="Hello world")
    pending = Content(
        id="content-123",
        title="Hello world",
        source_type="text",
        user_id="user-123",
        status="pending",
    )
    response = ContentResponse(
        id="content-123",
        title="Hello world",
        source_url=None,
        source_type="text",
        source_app_name=None,
        l0_summary=None,
        l1_outline=None,
        tags=[],
        status="pending",
        created_at=datetime(2026, 3, 11),
    )

    mock_pipeline = AsyncMock()
    mock_pipeline.create_pending_content = AsyncMock(return_value=pending)
    mock_db = AsyncMock()

    with patch("app.routers.content._get_pipeline", return_value=mock_pipeline):
            with patch(
                "app.routers.content._to_response",
                AsyncMock(return_value=response),
            ):
                with patch(
                    "app.routers.content._schedule_content_processing",
                    AsyncMock(),
                ) as schedule:
                    result = await create_content(
                        req=req,
                        db=mock_db,
                        user_id="user-123",
                    )

    assert result.status == "pending"
    mock_pipeline.create_pending_content.assert_awaited_once()
    mock_db.commit.assert_awaited_once()
    mock_db.refresh.assert_awaited_once_with(pending)
    schedule.assert_awaited_once_with(
        content_id="content-123",
        source_type="text",
        body="Hello world",
        user_id="user-123",
        db=mock_db,
    )


@pytest.mark.asyncio
async def test_schedule_content_processing_upserts_single_database_job(db_session):
    """Scheduler should reuse one queue row per content item."""
    from app.models.content_job import ContentJob
    from app.routers import content as content_router

    user_id = str(uuid4())

    await content_router._schedule_content_processing(
        content_id="content-123",
        source_type="text",
        body="Hello world",
        user_id=user_id,
        db=db_session,
    )
    await content_router._schedule_content_processing(
        content_id="content-123",
        source_type="text",
        body="Hello world",
        user_id=user_id,
        db=db_session,
    )
    await db_session.commit()

    rows = (await db_session.execute(select(ContentJob))).scalars().all()
    assert len(rows) == 1
    assert rows[0].content_id == "content-123"
    assert rows[0].status == "queued"


# ------------------------------------------------------------------ #
#  Router registration tests
# ------------------------------------------------------------------ #


class TestRouterRegistration:
    """Verify API routes are registered correctly on the FastAPI app."""

    def test_content_router_importable(self) -> None:
        from app.routers.content import router

        assert router is not None
        assert router.prefix == "/api/v1/content"

    def test_content_router_tags(self) -> None:
        from app.routers.content import router

        assert "content" in router.tags

    def test_routes_registered_on_app(self) -> None:
        from app.main import app

        paths = [route.path for route in app.routes]
        assert "/api/v1/content/" in paths
        assert "/api/v1/content/{content_id}" in paths
        assert "/api/v1/content/{content_id}/paragraphs" in paths
        assert "/api/v1/content/{content_id}/expand" in paths
        assert "/api/v1/content/{content_id}/ask" in paths

    def test_post_create_route_exists(self) -> None:
        from app.main import app

        post_routes = [
            route
            for route in app.routes
            if hasattr(route, "methods")
            and "POST" in route.methods
            and route.path == "/api/v1/content/"
        ]
        assert len(post_routes) == 1

    def test_get_list_route_exists(self) -> None:
        from app.main import app

        get_routes = [
            route
            for route in app.routes
            if hasattr(route, "methods")
            and "GET" in route.methods
            and route.path == "/api/v1/content/"
        ]
        assert len(get_routes) == 1

    def test_health_endpoint_still_exists(self) -> None:
        from app.main import app

        paths = [route.path for route in app.routes]
        assert "/health" in paths


# ------------------------------------------------------------------ #
#  Pipeline integration tests
# ------------------------------------------------------------------ #


@pytest.mark.asyncio
async def test_process_content_saves_tags_to_content_tags_table(db_session):
    """Test that pipeline saves AI-selected tags to content_tags table."""
    from app.models.content_tag import ContentTag
    from app.models.user_tag import UserTag
    from app.services.pipeline import ProcessingPipeline

    # Create user tags with UUID user_id (matching ORM model)
    test_user_id = str(uuid4())
    tag1 = UserTag(user_id=test_user_id, tag_name="技术")
    tag2 = UserTag(user_id=test_user_id, tag_name="学习")
    db_session.add_all([tag1, tag2])
    await db_session.commit()
    await db_session.refresh(tag1)
    await db_session.refresh(tag2)

    # Mock extractor to return text long enough for AI summarization (>= 500 chars)
    from app.services.extractor import ExtractedContent, ExtractedParagraph
    long_text = (
        "This is a comprehensive test article about technology and learning. " * 20
    )
    mock_extracted = ExtractedContent(
        title="Test Article",
        source_url=None,
        full_text=long_text,
        paragraphs=[
            ExtractedParagraph(
                anchor_id="¶1",
                text=long_text,
                position=0,
            )
        ],
    )

    # Mock summarizer to return tags
    from app.schemas.summary import ContentSummary, OutlinePoint
    mock_summary = ContentSummary(
        l0_summary="Test summary",
        l1_outline=[
            OutlinePoint(point="Main point", anchors=["¶1"])
        ],
        tags=["技术", "学习"],
        keywords=["test"],
    )

    pipeline = ProcessingPipeline()
    added_content_tags = []

    # Mock db.add to intercept ContentTag objects
    original_add = db_session.add
    def mock_add(obj):
        if isinstance(obj, ContentTag):
            added_content_tags.append(obj)
        return original_add(obj)

    # Mock db.execute to allow SELECT but skip FTS
    original_execute = db_session.execute
    async def mock_execute(stmt, *args, **kwargs):
        stmt_str = str(stmt)
        if "SELECT" in stmt_str.upper():
            return await original_execute(
                stmt, *args, **kwargs
            )
        if "to_tsvector" in stmt_str:
            return AsyncMock()
        return await original_execute(
            stmt, *args, **kwargs
        )

    # Mock the extractor, summarizer, and translator
    extract_mock = AsyncMock(return_value=mock_extracted)
    with patch.object(
        pipeline.extractor, "extract_text", extract_mock
    ):
        mock_summarizer = MagicMock()
        mock_summarizer.generate_summary = AsyncMock(
            return_value=mock_summary
        )

        summarizer_prop = property(
            lambda self: mock_summarizer
        )
        with patch.object(
            type(pipeline), "summarizer", summarizer_prop
        ):
            with patch.object(
                db_session, "add", side_effect=mock_add
            ):
                with patch.object(
                    db_session,
                    "execute",
                    side_effect=mock_execute,
                ):
                    with db_session.no_autoflush:
                        with patch.object(
                            db_session,
                            "flush",
                            AsyncMock(),
                        ):
                            with patch.object(
                                db_session,
                                "commit",
                                AsyncMock(),
                            ):
                                with patch.object(
                                    db_session,
                                    "refresh",
                                    AsyncMock(),
                                ):
                                    # Process content
                                    await pipeline.process(
                                        source_type="text",
                                        body=long_text,
                                        user_id=test_user_id,
                                        db=db_session,
                                    )

    # Verify content_tags were added
    assert len(added_content_tags) == 2, (
        f"Expected 2 content tags, got "
        f"{len(added_content_tags)}"
    )

    # Verify tag IDs match our created tags
    tag_ids = {ct.tag_id for ct in added_content_tags}
    assert tag1.id in tag_ids, (
        f"Tag '技术' (id={tag1.id}) was not linked to content"
    )
    assert tag2.id in tag_ids, (
        f"Tag '学习' (id={tag2.id}) was not linked to content"
    )

    # Verify user_id is set correctly
    for ct in added_content_tags:
        assert ct.user_id == test_user_id, (
            f"ContentTag user_id mismatch, got {ct.user_id}"
        )


@pytest.mark.asyncio
async def test_process_content_skips_nonexistent_tags(db_session):
    """Test that pipeline skips tags that don't exist in user's library."""
    from app.models.content_tag import ContentTag
    from app.models.user_tag import UserTag
    from app.services.pipeline import ProcessingPipeline

    # Create only ONE tag with UUID user_id
    test_user_id = str(uuid4())
    tag1 = UserTag(user_id=test_user_id, tag_name="技术")
    db_session.add(tag1)
    await db_session.commit()
    await db_session.refresh(tag1)

    # Mock extractor to return text long enough for AI summarization (>= 500 chars)
    from app.services.extractor import ExtractedContent, ExtractedParagraph
    long_text = (
        "This is a comprehensive test article about technology and learning. " * 20
    )
    mock_extracted = ExtractedContent(
        title="Test Article",
        source_url=None,
        full_text=long_text,
        paragraphs=[
            ExtractedParagraph(
                anchor_id="¶1",
                text=long_text,
                position=0,
            )
        ],
    )

    # Mock summarizer to return tags including one that doesn't exist
    from app.schemas.summary import ContentSummary, OutlinePoint
    mock_summary = ContentSummary(
        l0_summary="Test summary",
        l1_outline=[
            OutlinePoint(point="Main point", anchors=["¶1"])
        ],
        tags=["技术", "不存在的标签"],
        keywords=["test"],
    )

    pipeline = ProcessingPipeline()
    added_content_tags = []

    # Mock db.add to intercept ContentTag objects
    original_add = db_session.add
    def mock_add(obj):
        if isinstance(obj, ContentTag):
            added_content_tags.append(obj)
        return original_add(obj)

    # Mock db.execute to allow SELECT but skip FTS
    original_execute = db_session.execute
    async def mock_execute(stmt, *args, **kwargs):
        stmt_str = str(stmt)
        if "SELECT" in stmt_str.upper():
            return await original_execute(
                stmt, *args, **kwargs
            )
        if "to_tsvector" in stmt_str:
            return AsyncMock()
        return await original_execute(
            stmt, *args, **kwargs
        )

    # Mock the extractor, summarizer, and translator
    extract_mock = AsyncMock(return_value=mock_extracted)
    with patch.object(
        pipeline.extractor, "extract_text", extract_mock
    ):
        mock_summarizer = MagicMock()
        mock_summarizer.generate_summary = AsyncMock(
            return_value=mock_summary
        )

        summarizer_prop = property(
            lambda self: mock_summarizer
        )
        with patch.object(
            type(pipeline), "summarizer", summarizer_prop
        ):
            with patch.object(
                db_session, "add", side_effect=mock_add
            ):
                with patch.object(
                    db_session,
                    "execute",
                    side_effect=mock_execute,
                ):
                    with db_session.no_autoflush:
                        with patch.object(
                            db_session,
                            "flush",
                            AsyncMock(),
                        ):
                            with patch.object(
                                db_session,
                                "commit",
                                AsyncMock(),
                            ):
                                with patch.object(
                                    db_session,
                                    "refresh",
                                    AsyncMock(),
                                ):
                                    # Process content
                                    await pipeline.process(
                                        source_type="text",
                                        body=long_text,
                                        user_id=test_user_id,
                                        db=db_session,
                                    )

    # Verify only ONE content_tag was created
    assert len(added_content_tags) == 1, (
        "Should only create relationship for existing tag, "
        f"got {len(added_content_tags)}"
    )

    # Verify the tag is the correct one
    assert added_content_tags[0].tag_id == tag1.id, (
        f"ContentTag should link to '技术' tag "
        f"(id={tag1.id})"
    )
    assert added_content_tags[0].user_id == test_user_id, (
        "ContentTag user_id mismatch"
    )


@pytest.mark.asyncio
async def test_process_pending_content_marks_failed_when_processing_raises():
    """Background processing should leave a visible failed state on errors."""
    from app.models.content import Content
    from app.services.pipeline import FAILED_IMPORT_SUMMARY, ProcessingPipeline

    content = Content(
        id="failed-123",
        title="Pending",
        source_type="text",
        user_id="user-123",
        status="pending",
    )
    db = AsyncMock()
    db.get = AsyncMock(side_effect=[content, content])

    pipeline = ProcessingPipeline()

    with patch.object(
        pipeline,
        "_process_into_content",
        AsyncMock(side_effect=RuntimeError("boom")),
    ):
        result = await pipeline.process_pending_content(
            content_id="failed-123",
            source_type="text",
            body="Hello world",
            user_id="user-123",
            db=db,
        )

    assert result is content
    assert content.status == "failed"
    assert content.l0_summary == FAILED_IMPORT_SUMMARY
    assert content.l1_outline == []
    assert content.processing_attempts == 1
    assert content.processing_started_at is not None
    assert content.processing_finished_at is not None
    assert content.processing_error is not None
    assert "RuntimeError" in content.processing_error
    assert "boom" in content.processing_error
    assert db.rollback.await_count == 1
    assert db.commit.await_count == 2


@pytest.mark.asyncio
async def test_process_pending_content_promotes_content_to_ready():
    """Background processing should update the placeholder row in place."""
    from app.models.content import Content
    from app.schemas.summary import ContentSummary, OutlinePoint
    from app.services.extractor import ExtractedContent, ExtractedParagraph
    from app.services.pipeline import ProcessingPipeline

    content = Content(
        id="ready-123",
        title="Pending",
        source_type="text",
        user_id="user-123",
        status="pending",
    )
    db = AsyncMock()
    db.get = AsyncMock(return_value=content)

    extracted = ExtractedContent(
        title="Real title",
        source_url=None,
        full_text="A" * 800,
        paragraphs=[
            ExtractedParagraph(anchor_id="¶1", text="Paragraph", position=0)
        ],
    )
    summary = ContentSummary(
        l0_summary="Summary",
        l1_outline=[OutlinePoint(point="Point", anchors=["¶1"])],
        tags=[],
        keywords=["kw"],
    )

    pipeline = ProcessingPipeline()

    with patch.object(pipeline, "_extract_content", AsyncMock(return_value=extracted)):
        with patch.object(
            pipeline,
            "_summarize_content",
            AsyncMock(return_value=(summary, "en")),
        ):
            with patch.object(
                pipeline,
                "_replace_related_rows",
                AsyncMock(),
            ) as replace_rows:
                with patch.object(
                    pipeline,
                    "_update_full_text_search",
                    AsyncMock(),
                ) as update_fts:
                    result = await pipeline.process_pending_content(
                        content_id="ready-123",
                        source_type="text",
                        body="Hello world",
                        user_id="user-123",
                        db=db,
                    )

    assert result is content
    assert content.status == "ready"
    assert content.title == "Real title"
    assert content.l0_summary == "Summary"
    assert content.source_language == "en"
    assert content.full_text == "A" * 800
    assert content.processing_attempts == 1
    assert content.processing_started_at is not None
    assert content.processing_finished_at is not None
    assert content.processing_error is None
    replace_rows.assert_awaited_once()
    update_fts.assert_awaited_once_with(content_id="ready-123", db=db)

"""Tests for the content processing pipeline, schemas, and router registration.

These tests require NO database, NO API keys, and NO network access.
They verify schema validation, structural correctness, and route registration.
"""

import pytest
from datetime import datetime

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

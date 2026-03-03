"""Tests for podcast generation service, storage service, and router registration.

These tests require NO database, NO API keys, and NO network access.
They verify class structure, method signatures, and route registration.
"""



# ------------------------------------------------------------------ #
#  StorageService structural tests
# ------------------------------------------------------------------ #


class TestStorageServiceStructure:
    """Verify StorageService class structure without calling external services."""

    def test_importable(self) -> None:
        from app.services.storage import StorageService

        assert StorageService is not None

    def test_instantiable(self) -> None:
        from app.services.storage import StorageService

        service = StorageService()
        assert service is not None

    def test_s3_client_is_lazy(self) -> None:
        """Verify that StorageService does not create the S3 client at init time."""
        from app.services.storage import StorageService

        service = StorageService()
        assert service._s3 is None

    def test_has_upload_audio_method(self) -> None:
        from app.services.storage import StorageService

        assert hasattr(StorageService, "upload_audio")
        assert callable(getattr(StorageService, "upload_audio"))

    def test_has_get_presigned_url_method(self) -> None:
        from app.services.storage import StorageService

        assert hasattr(StorageService, "get_presigned_url")
        assert callable(getattr(StorageService, "get_presigned_url"))

    def test_has_bucket_property(self) -> None:
        from app.services.storage import StorageService

        assert isinstance(
            getattr(StorageService, "bucket", None), property
        )

    def test_has_s3_property(self) -> None:
        from app.services.storage import StorageService

        assert isinstance(
            getattr(StorageService, "s3", None), property
        )


# ------------------------------------------------------------------ #
#  PodcastService structural tests
# ------------------------------------------------------------------ #


class TestPodcastServiceStructure:
    """Verify PodcastService class structure without calling external services."""

    def test_importable(self) -> None:
        from app.services.podcast import PodcastService

        assert PodcastService is not None

    def test_instantiable(self) -> None:
        from app.services.podcast import PodcastService

        service = PodcastService()
        assert service is not None

    def test_client_is_lazy(self) -> None:
        """PodcastService should not create Anthropic client at init."""
        from app.services.podcast import PodcastService

        service = PodcastService()
        assert service._client is None

    def test_storage_is_lazy(self) -> None:
        """PodcastService should not create StorageService at init."""
        from app.services.podcast import PodcastService

        service = PodcastService()
        assert service._storage is None

    def test_has_generate_method(self) -> None:
        from app.services.podcast import PodcastService

        assert hasattr(PodcastService, "generate")
        assert callable(getattr(PodcastService, "generate"))

    def test_has_generate_script_method(self) -> None:
        from app.services.podcast import PodcastService

        assert hasattr(PodcastService, "_generate_script")
        assert callable(getattr(PodcastService, "_generate_script"))

    def test_has_generate_audio_method(self) -> None:
        from app.services.podcast import PodcastService

        assert hasattr(PodcastService, "_generate_audio")
        assert callable(getattr(PodcastService, "_generate_audio"))

    def test_has_client_property(self) -> None:
        from app.services.podcast import PodcastService

        assert isinstance(
            getattr(PodcastService, "client", None), property
        )

    def test_has_storage_property(self) -> None:
        from app.services.podcast import PodcastService

        assert isinstance(
            getattr(PodcastService, "storage", None), property
        )


# ------------------------------------------------------------------ #
#  Podcast router structural tests
# ------------------------------------------------------------------ #


class TestPodcastRouterRegistration:
    """Verify podcast API routes are registered correctly on the FastAPI app."""

    def test_podcast_router_importable(self) -> None:
        from app.routers.podcast import router

        assert router is not None
        assert router.prefix == "/api/v1/podcast"

    def test_podcast_router_tags(self) -> None:
        from app.routers.podcast import router

        assert "podcast" in router.tags

    def test_generate_route_registered_on_app(self) -> None:
        from app.main import app

        paths = [route.path for route in app.routes]
        assert "/api/v1/podcast/{content_id}/generate" in paths

    def test_get_route_registered_on_app(self) -> None:
        from app.main import app

        paths = [route.path for route in app.routes]
        assert "/api/v1/podcast/{content_id}" in paths

    def test_generate_is_post(self) -> None:
        from app.main import app

        post_routes = [
            route
            for route in app.routes
            if hasattr(route, "methods")
            and "POST" in route.methods
            and route.path == "/api/v1/podcast/{content_id}/generate"
        ]
        assert len(post_routes) == 1

    def test_get_podcast_is_get(self) -> None:
        from app.main import app

        get_routes = [
            route
            for route in app.routes
            if hasattr(route, "methods")
            and "GET" in route.methods
            and route.path == "/api/v1/podcast/{content_id}"
        ]
        assert len(get_routes) == 1

    def test_health_endpoint_still_exists(self) -> None:
        from app.main import app

        paths = [route.path for route in app.routes]
        assert "/health" in paths

    def test_content_routes_still_exist(self) -> None:
        from app.main import app

        paths = [route.path for route in app.routes]
        assert "/api/v1/content/" in paths
        assert "/api/v1/content/{content_id}" in paths

    def test_search_route_still_exists(self) -> None:
        from app.main import app

        paths = [route.path for route in app.routes]
        assert "/api/v1/search/" in paths


# ------------------------------------------------------------------ #
#  Lazy initialization tests
# ------------------------------------------------------------------ #


class TestPodcastLazyInit:
    """Verify the lazy initialization pattern for PodcastService."""

    def test_get_service_returns_podcast_service(self) -> None:
        import app.routers.podcast as podcast_mod
        from app.services.podcast import PodcastService

        # Reset the module-level singleton so we get a fresh one
        podcast_mod._service = None
        service = podcast_mod._get_service()
        assert isinstance(service, PodcastService)
        # Clean up
        podcast_mod._service = None

    def test_get_service_returns_same_instance(self) -> None:
        import app.routers.podcast as podcast_mod

        podcast_mod._service = None
        service1 = podcast_mod._get_service()
        service2 = podcast_mod._get_service()
        assert service1 is service2
        # Clean up
        podcast_mod._service = None


# ------------------------------------------------------------------ #
#  Podcast model structural tests
# ------------------------------------------------------------------ #


class TestPodcastModel:
    """Verify Podcast ORM model has the expected columns."""

    def test_importable(self) -> None:
        from app.models.podcast import Podcast

        assert Podcast is not None

    def test_tablename(self) -> None:
        from app.models.podcast import Podcast

        assert Podcast.__tablename__ == "podcasts"

    def test_has_expected_columns(self) -> None:
        from app.models.podcast import Podcast

        column_names = [c.name for c in Podcast.__table__.columns]
        assert "id" in column_names
        assert "content_id" in column_names
        assert "audio_url" in column_names
        assert "script" in column_names
        assert "chapters" in column_names
        assert "status" in column_names
        assert "created_at" in column_names

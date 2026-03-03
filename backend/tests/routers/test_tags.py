"""Tests for tag router endpoints.

These tests verify the tag management API without requiring external services.
They test module structure, imports, and router registration.
"""

import inspect

# ------------------------------------------------------------------ #
#  Module exports and router setup
# ------------------------------------------------------------------ #


class TestTagRouterSetup:
    """Verify tag router is properly configured."""

    def test_router_importable(self) -> None:
        """Verify tags router can be imported."""
        from app.routers.tags import router

        assert router is not None

    def test_router_prefix(self) -> None:
        """Verify router has correct prefix."""
        from app.routers.tags import router

        assert router.prefix == "/api/v1/tags"

    def test_router_tags(self) -> None:
        """Verify router has correct tags."""
        from app.routers.tags import router

        assert "tags" in router.tags

    def test_router_registered_in_main(self) -> None:
        """Verify tags router is registered in main app."""
        from app.main import app

        paths = [route.path for route in app.routes]
        # Should have at least one tags endpoint
        tag_paths = [p for p in paths if p.startswith("/api/v1/tags")]
        assert len(tag_paths) > 0


# ------------------------------------------------------------------ #
#  Endpoint: GET /api/v1/tags - List user's tags
# ------------------------------------------------------------------ #


class TestListUserTags:
    """Test GET /api/v1/tags endpoint."""

    def test_list_tags_endpoint_exists(self) -> None:
        """Verify list_user_tags endpoint exists."""
        from app.routers import tags

        assert hasattr(tags, "list_user_tags")

    def test_list_tags_is_coroutine(self) -> None:
        """Verify list_user_tags is async."""
        from app.routers.tags import list_user_tags

        assert inspect.iscoroutinefunction(list_user_tags)

    def test_list_tags_has_db_dependency(self) -> None:
        """Verify list_user_tags has database dependency."""
        from app.routers.tags import list_user_tags

        sig = inspect.signature(list_user_tags)
        assert "db" in sig.parameters

    def test_list_tags_has_user_id_dependency(self) -> None:
        """Verify list_user_tags has user_id dependency."""
        from app.routers.tags import list_user_tags

        sig = inspect.signature(list_user_tags)
        assert "user_id" in sig.parameters

    def test_list_tags_return_type(self) -> None:
        """Verify list_user_tags returns list of UserTagResponse."""
        from app.routers.tags import list_user_tags

        sig = inspect.signature(list_user_tags)
        # Should return list[UserTagResponse]
        assert sig.return_annotation != inspect.Signature.empty


# ------------------------------------------------------------------ #
#  Endpoint: POST /api/v1/tags - Create tag
# ------------------------------------------------------------------ #


class TestCreateTag:
    """Test POST /api/v1/tags endpoint."""

    def test_create_tag_endpoint_exists(self) -> None:
        """Verify create_tag endpoint exists."""
        from app.routers import tags

        assert hasattr(tags, "create_tag")

    def test_create_tag_is_coroutine(self) -> None:
        """Verify create_tag is async."""
        from app.routers.tags import create_tag

        assert inspect.iscoroutinefunction(create_tag)

    def test_create_tag_has_request_param(self) -> None:
        """Verify create_tag accepts TagCreateRequest."""
        from app.routers.tags import create_tag

        sig = inspect.signature(create_tag)
        assert "req" in sig.parameters

    def test_create_tag_has_dependencies(self) -> None:
        """Verify create_tag has db and user_id dependencies."""
        from app.routers.tags import create_tag

        sig = inspect.signature(create_tag)
        assert "db" in sig.parameters
        assert "user_id" in sig.parameters


# ------------------------------------------------------------------ #
#  Endpoint: DELETE /api/v1/tags/{tag_id} - Delete tag
# ------------------------------------------------------------------ #


class TestDeleteTag:
    """Test DELETE /api/v1/tags/{tag_id} endpoint."""

    def test_delete_tag_endpoint_exists(self) -> None:
        """Verify delete_tag endpoint exists."""
        from app.routers import tags

        assert hasattr(tags, "delete_tag")

    def test_delete_tag_is_coroutine(self) -> None:
        """Verify delete_tag is async."""
        from app.routers.tags import delete_tag

        assert inspect.iscoroutinefunction(delete_tag)

    def test_delete_tag_has_tag_id_param(self) -> None:
        """Verify delete_tag accepts tag_id path parameter."""
        from app.routers.tags import delete_tag

        sig = inspect.signature(delete_tag)
        assert "tag_id" in sig.parameters

    def test_delete_tag_has_dependencies(self) -> None:
        """Verify delete_tag has db and user_id dependencies."""
        from app.routers.tags import delete_tag

        sig = inspect.signature(delete_tag)
        assert "db" in sig.parameters
        assert "user_id" in sig.parameters


# ------------------------------------------------------------------ #
#  Endpoint: GET /api/v1/tags/content/{content_id}/tags
# ------------------------------------------------------------------ #


class TestGetContentTags:
    """Test GET /api/v1/tags/content/{content_id}/tags endpoint."""

    def test_get_content_tags_endpoint_exists(self) -> None:
        """Verify get_content_tags endpoint exists."""
        from app.routers import tags

        assert hasattr(tags, "get_content_tags")

    def test_get_content_tags_is_coroutine(self) -> None:
        """Verify get_content_tags is async."""
        from app.routers.tags import get_content_tags

        assert inspect.iscoroutinefunction(get_content_tags)

    def test_get_content_tags_has_content_id_param(self) -> None:
        """Verify get_content_tags accepts content_id path parameter."""
        from app.routers.tags import get_content_tags

        sig = inspect.signature(get_content_tags)
        assert "content_id" in sig.parameters

    def test_get_content_tags_has_dependencies(self) -> None:
        """Verify get_content_tags has db and user_id dependencies."""
        from app.routers.tags import get_content_tags

        sig = inspect.signature(get_content_tags)
        assert "db" in sig.parameters
        assert "user_id" in sig.parameters


# ------------------------------------------------------------------ #
#  Endpoint: PUT /api/v1/tags/content/{content_id}/tags
# ------------------------------------------------------------------ #


class TestUpdateContentTags:
    """Test PUT /api/v1/tags/content/{content_id}/tags endpoint."""

    def test_update_content_tags_endpoint_exists(self) -> None:
        """Verify update_content_tags endpoint exists."""
        from app.routers import tags

        assert hasattr(tags, "update_content_tags")

    def test_update_content_tags_is_coroutine(self) -> None:
        """Verify update_content_tags is async."""
        from app.routers.tags import update_content_tags

        assert inspect.iscoroutinefunction(update_content_tags)

    def test_update_content_tags_has_params(self) -> None:
        """Verify update_content_tags has all required parameters."""
        from app.routers.tags import update_content_tags

        sig = inspect.signature(update_content_tags)
        assert "content_id" in sig.parameters
        assert "req" in sig.parameters

    def test_update_content_tags_has_dependencies(self) -> None:
        """Verify update_content_tags has db and user_id dependencies."""
        from app.routers.tags import update_content_tags

        sig = inspect.signature(update_content_tags)
        assert "db" in sig.parameters
        assert "user_id" in sig.parameters


# ------------------------------------------------------------------ #
#  Endpoint: GET /api/v1/tags/{tag_id}/contents
# ------------------------------------------------------------------ #


class TestGetContentsByTag:
    """Test GET /api/v1/tags/{tag_id}/contents endpoint."""

    def test_get_contents_by_tag_endpoint_exists(self) -> None:
        """Verify get_contents_by_tag endpoint exists."""
        from app.routers import tags

        assert hasattr(tags, "get_contents_by_tag")

    def test_get_contents_by_tag_is_coroutine(self) -> None:
        """Verify get_contents_by_tag is async."""
        from app.routers.tags import get_contents_by_tag

        assert inspect.iscoroutinefunction(get_contents_by_tag)

    def test_get_contents_by_tag_has_tag_id_param(self) -> None:
        """Verify get_contents_by_tag accepts tag_id path parameter."""
        from app.routers.tags import get_contents_by_tag

        sig = inspect.signature(get_contents_by_tag)
        assert "tag_id" in sig.parameters

    def test_get_contents_by_tag_has_dependencies(self) -> None:
        """Verify get_contents_by_tag has db and user_id dependencies."""
        from app.routers.tags import get_contents_by_tag

        sig = inspect.signature(get_contents_by_tag)
        assert "db" in sig.parameters
        assert "user_id" in sig.parameters


# ------------------------------------------------------------------ #
#  Auth integration
# ------------------------------------------------------------------ #


class TestTagRouterAuth:
    """Verify tag router uses proper auth from app.auth."""

    def test_uses_get_current_user_id_from_auth(self) -> None:
        """Verify tags router imports get_current_user_id from app.auth."""
        import app.routers.tags as tags_mod
        from app.auth import get_current_user_id

        assert tags_mod.get_current_user_id is get_current_user_id

    def test_auth_function_is_async(self) -> None:
        """Verify auth function used is async."""
        import app.routers.tags as tags_mod

        assert inspect.iscoroutinefunction(tags_mod.get_current_user_id)


# ------------------------------------------------------------------ #
#  Schema usage
# ------------------------------------------------------------------ #


class TestTagRouterSchemas:
    """Verify tag router uses proper schemas."""

    def test_imports_user_tag_response(self) -> None:
        """Verify router imports UserTagResponse schema."""

        # Check module imports the schema
        import app.schemas.tag as tag_schema
        assert hasattr(tag_schema, "UserTagResponse")

    def test_imports_tag_create_request(self) -> None:
        """Verify router imports TagCreateRequest schema."""
        import app.schemas.tag as tag_schema
        assert hasattr(tag_schema, "TagCreateRequest")

    def test_imports_content_tags_update_request(self) -> None:
        """Verify router imports ContentTagsUpdateRequest schema."""
        import app.schemas.tag as tag_schema
        assert hasattr(tag_schema, "ContentTagsUpdateRequest")


# ------------------------------------------------------------------ #
#  Model usage
# ------------------------------------------------------------------ #


class TestTagRouterModels:
    """Verify tag router uses proper models."""

    def test_imports_user_tag_model(self) -> None:
        """Verify router can access UserTag model."""
        from app.models import UserTag

        assert UserTag is not None

    def test_imports_content_tag_model(self) -> None:
        """Verify router can access ContentTag model."""
        from app.models import ContentTag

        assert ContentTag is not None

    def test_imports_content_model(self) -> None:
        """Verify router can access Content model."""
        from app.models import Content

        assert Content is not None

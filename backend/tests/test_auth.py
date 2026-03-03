"""Tests for Clerk JWT authentication middleware.

These tests require NO external services, NO API keys, and NO network access.
They verify module structure, security scheme, and that router stubs are removed.
"""

import inspect

from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer

# ------------------------------------------------------------------ #
#  Module exports
# ------------------------------------------------------------------ #


class TestAuthModuleExports:
    """Verify auth.py exports the expected symbols."""

    def test_get_current_user_id_importable(self) -> None:
        from app.auth import get_current_user_id

        assert get_current_user_id is not None

    def test_security_importable(self) -> None:
        from app.auth import security

        assert security is not None

    def test_security_is_http_bearer(self) -> None:
        from app.auth import security

        assert isinstance(security, HTTPBearer)


# ------------------------------------------------------------------ #
#  Function signature
# ------------------------------------------------------------------ #


class TestGetCurrentUserIdSignature:
    """Verify the function signature accepts HTTPAuthorizationCredentials."""

    def test_is_coroutine(self) -> None:
        from app.auth import get_current_user_id

        assert inspect.iscoroutinefunction(get_current_user_id)

    def test_has_credentials_parameter(self) -> None:
        from app.auth import get_current_user_id

        sig = inspect.signature(get_current_user_id)
        assert "credentials" in sig.parameters

    def test_credentials_annotation(self) -> None:
        from app.auth import get_current_user_id

        sig = inspect.signature(get_current_user_id)
        param = sig.parameters["credentials"]
        assert param.annotation is HTTPAuthorizationCredentials

    def test_return_annotation_is_str(self) -> None:
        from app.auth import get_current_user_id

        sig = inspect.signature(get_current_user_id)
        assert sig.return_annotation is str


# ------------------------------------------------------------------ #
#  Stub removal verification
# ------------------------------------------------------------------ #


class TestStubsRemoved:
    """Verify that content and search routers no longer have local stubs."""

    def test_content_router_no_local_stub(self) -> None:
        """content.py should import get_current_user_id from app.auth."""
        import app.routers.content as content_mod

        # The function should exist (imported), but it should be the one from app.auth
        from app.auth import get_current_user_id

        assert content_mod.get_current_user_id is get_current_user_id

    def test_search_router_no_local_stub(self) -> None:
        """search.py should import get_current_user_id from app.auth."""
        import app.routers.search as search_mod
        from app.auth import get_current_user_id

        assert search_mod.get_current_user_id is get_current_user_id

    def test_content_router_stub_is_not_sync(self) -> None:
        """Auth function used by content router should be async."""
        import app.routers.content as content_mod

        assert inspect.iscoroutinefunction(content_mod.get_current_user_id)

    def test_search_router_stub_is_not_sync(self) -> None:
        """Auth function used by search router should be async."""
        import app.routers.search as search_mod

        assert inspect.iscoroutinefunction(search_mod.get_current_user_id)


# ------------------------------------------------------------------ #
#  Integration: routers still register correctly with auth dependency
# ------------------------------------------------------------------ #


class TestRoutersStillWork:
    """Verify routers still register correctly after auth change."""

    def test_content_routes_registered(self) -> None:
        from app.main import app

        paths = [route.path for route in app.routes]
        assert "/api/v1/content/" in paths
        assert "/api/v1/content/{content_id}" in paths

    def test_search_route_registered(self) -> None:
        from app.main import app

        paths = [route.path for route in app.routes]
        assert "/api/v1/search/" in paths

    def test_health_endpoint_still_exists(self) -> None:
        from app.main import app

        paths = [route.path for route in app.routes]
        assert "/health" in paths

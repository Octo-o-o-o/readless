"""Tests for the search agent, schemas, and router registration.

These tests require NO database, NO API keys, and NO network access.
They verify schema validation, structural correctness, and route registration.
"""

import pytest

# ------------------------------------------------------------------ #
#  SearchRequest schema
# ------------------------------------------------------------------ #


class TestSearchRequest:
    """Verify SearchRequest pydantic model validates correctly."""

    def test_valid_request(self) -> None:
        from app.routers.search import SearchRequest

        req = SearchRequest(query="articles about machine learning")
        assert req.query == "articles about machine learning"

    def test_missing_query_field(self) -> None:
        from app.routers.search import SearchRequest

        with pytest.raises(Exception):
            SearchRequest()  # type: ignore[call-arg]

    def test_empty_query(self) -> None:
        from app.routers.search import SearchRequest

        req = SearchRequest(query="")
        assert req.query == ""

    def test_serialization(self) -> None:
        from app.routers.search import SearchRequest

        req = SearchRequest(query="find PDFs about Python")
        data = req.model_dump()
        assert data == {"query": "find PDFs about Python"}

    def test_json_roundtrip(self) -> None:
        from app.routers.search import SearchRequest

        original = SearchRequest(query="recent AI papers")
        json_str = original.model_dump_json()
        restored = SearchRequest.model_validate_json(json_str)
        assert restored == original

    def test_from_dict(self) -> None:
        from app.routers.search import SearchRequest

        data = {"query": "test query"}
        req = SearchRequest(**data)
        assert req.query == "test query"


# ------------------------------------------------------------------ #
#  SearchAgent structural tests
# ------------------------------------------------------------------ #


class TestSearchAgentStructure:
    """Verify SearchAgent class structure without calling external services."""

    def test_importable(self) -> None:
        from app.services.search_agent import SearchAgent

        assert SearchAgent is not None

    def test_has_search_method(self) -> None:
        from app.services.search_agent import SearchAgent

        assert hasattr(SearchAgent, "search")
        assert callable(getattr(SearchAgent, "search"))

    def test_has_parse_intent_method(self) -> None:
        from app.services.search_agent import SearchAgent

        assert hasattr(SearchAgent, "_parse_intent")
        assert callable(getattr(SearchAgent, "_parse_intent"))

    def test_has_search_index_method(self) -> None:
        from app.services.search_agent import SearchAgent

        assert hasattr(SearchAgent, "_search_index")
        assert callable(getattr(SearchAgent, "_search_index"))

    def test_has_rank_candidates_method(self) -> None:
        from app.services.search_agent import SearchAgent

        assert hasattr(SearchAgent, "_rank_candidates")
        assert callable(getattr(SearchAgent, "_rank_candidates"))

    def test_has_generate_answer_method(self) -> None:
        from app.services.search_agent import SearchAgent

        assert hasattr(SearchAgent, "_generate_answer")
        assert callable(getattr(SearchAgent, "_generate_answer"))


# ------------------------------------------------------------------ #
#  Router registration tests
# ------------------------------------------------------------------ #


class TestSearchRouterRegistration:
    """Verify search API routes are registered correctly on the FastAPI app."""

    def test_search_router_importable(self) -> None:
        from app.routers.search import router

        assert router is not None
        assert router.prefix == "/api/v1/search"

    def test_search_router_tags(self) -> None:
        from app.routers.search import router

        assert "search" in router.tags

    def test_search_route_registered_on_app(self) -> None:
        from app.main import app

        paths = [route.path for route in app.routes]
        assert "/api/v1/search/" in paths

    def test_search_post_route_exists(self) -> None:
        from app.main import app

        post_routes = [
            route
            for route in app.routes
            if hasattr(route, "methods")
            and "POST" in route.methods
            and route.path == "/api/v1/search/"
        ]
        assert len(post_routes) == 1

    def test_health_endpoint_still_exists(self) -> None:
        from app.main import app

        paths = [route.path for route in app.routes]
        assert "/health" in paths

    def test_content_routes_still_exist(self) -> None:
        from app.main import app

        paths = [route.path for route in app.routes]
        assert "/api/v1/content/" in paths
        assert "/api/v1/content/{content_id}" in paths


# ------------------------------------------------------------------ #
#  Lazy initialization tests
# ------------------------------------------------------------------ #


class TestSearchLazyInit:
    """Verify the lazy initialization pattern for SearchAgent."""

    def test_get_agent_returns_search_agent(self) -> None:
        import app.routers.search as search_mod
        from app.services.search_agent import SearchAgent

        # Reset the module-level singleton so we get a fresh one
        search_mod._agent = None
        agent = search_mod._get_agent()
        assert isinstance(agent, SearchAgent)
        # Clean up
        search_mod._agent = None

    def test_get_agent_returns_same_instance(self) -> None:
        import app.routers.search as search_mod

        search_mod._agent = None
        agent1 = search_mod._get_agent()
        agent2 = search_mod._get_agent()
        assert agent1 is agent2
        # Clean up
        search_mod._agent = None

    def test_client_is_lazy(self) -> None:
        """Verify that SearchAgent does not create the Anthropic client at init time."""
        from app.services.search_agent import SearchAgent

        agent = SearchAgent()
        # The internal _client should be None until first access
        assert agent._client is None

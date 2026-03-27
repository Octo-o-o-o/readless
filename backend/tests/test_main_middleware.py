"""Tests for main app middleware helpers."""

from __future__ import annotations

from unittest.mock import AsyncMock, patch

from httpx import ASGITransport, AsyncClient
from starlette.requests import Request
from starlette.responses import JSONResponse, RedirectResponse


def _make_request(headers: list[tuple[bytes, bytes]]) -> Request:
    return Request(
        {
            "type": "http",
            "http_version": "1.1",
            "method": "GET",
            "scheme": "http",
            "path": "/",
            "raw_path": b"/",
            "query_string": b"",
            "headers": headers,
            "client": ("127.0.0.1", 1234),
            "server": ("testserver", 80),
        }
    )


async def _redirect_call_next(_request: Request):
    return RedirectResponse("http://example.com/next", status_code=307)


async def _no_redirect_call_next(_request: Request):
    return RedirectResponse("http://example.com/next", status_code=307)


async def _success_call_next(_request: Request):
    return RedirectResponse("http://example.com/next", status_code=302)


async def _json_call_next(request: Request):
    return JSONResponse(
        {
            "request_id": getattr(request.state, "request_id", None),
        }
    )


async def test_https_redirect_middleware_upgrades_forwarded_https_locations():
    from app.main import HTTPSRedirectMiddleware

    middleware = HTTPSRedirectMiddleware(app=lambda *_args, **_kwargs: None)
    request = _make_request(headers=[(b"x-forwarded-proto", b"https")])

    response = await middleware.dispatch(request, _redirect_call_next)

    assert response.headers["location"] == "https://example.com/next"


async def test_https_redirect_middleware_leaves_other_redirects_unchanged():
    from app.main import HTTPSRedirectMiddleware

    middleware = HTTPSRedirectMiddleware(app=lambda *_args, **_kwargs: None)
    request = _make_request(headers=[(b"x-forwarded-proto", b"http")])

    response = await middleware.dispatch(request, _no_redirect_call_next)

    assert response.headers["location"] == "http://example.com/next"


async def test_operational_headers_middleware_adds_request_trace_headers():
    from app.main import OperationalHeadersMiddleware

    middleware = OperationalHeadersMiddleware(app=lambda *_args, **_kwargs: None)
    request = _make_request(headers=[])

    response = await middleware.dispatch(request, _json_call_next)

    assert response.headers["X-Request-ID"]
    assert response.headers["X-Content-Type-Options"] == "nosniff"
    assert response.headers["X-Frame-Options"] == "DENY"
    assert response.headers["Referrer-Policy"] == "same-origin"
    assert float(response.headers["X-Process-Time-Ms"]) >= 0
    assert b'"request_id":"' in response.body


async def test_operational_headers_middleware_preserves_incoming_request_id():
    from app.main import OperationalHeadersMiddleware

    middleware = OperationalHeadersMiddleware(app=lambda *_args, **_kwargs: None)
    request = _make_request(headers=[(b"x-request-id", b"req-123")])

    response = await middleware.dispatch(request, _json_call_next)

    assert response.headers["X-Request-ID"] == "req-123"
    assert b'"request_id":"req-123"' in response.body


async def test_health_ready_returns_ok_when_database_probe_succeeds():
    from app.main import app

    with patch("app.main.check_database_readiness", new=AsyncMock()) as probe:
        transport = ASGITransport(app=app)
        async with AsyncClient(transport=transport, base_url="http://test") as client:
            response = await client.get("/health/ready")

    probe.assert_awaited_once()
    assert response.status_code == 200
    assert response.json() == {"status": "ok", "checks": {"database": "ok"}}


async def test_health_ready_returns_503_when_database_probe_fails():
    from app.main import app

    with patch(
        "app.main.check_database_readiness",
        new=AsyncMock(side_effect=RuntimeError("db down")),
    ) as probe:
        transport = ASGITransport(app=app)
        async with AsyncClient(transport=transport, base_url="http://test") as client:
            response = await client.get("/health/ready")

    probe.assert_awaited_once()
    assert response.status_code == 503
    assert response.json() == {
        "status": "degraded",
        "checks": {"database": "error"},
    }

"""Tests for transactional email delivery helpers."""

from __future__ import annotations

from types import SimpleNamespace
from unittest.mock import patch

import httpx
import pytest

from app.services.email_service import ResendEmailService


class FakeAsyncClient:
    def __init__(self, response, captured):
        self._response = response
        self._captured = captured

    async def __aenter__(self):
        return self

    async def __aexit__(self, exc_type, exc, tb):
        return False

    async def post(self, url, json, headers):
        self._captured.append({"url": url, "json": json, "headers": headers})
        return self._response


class ExplodingAsyncClient:
    async def __aenter__(self):
        return self

    async def __aexit__(self, exc_type, exc, tb):
        return False

    async def post(self, url, json, headers):
        raise httpx.ConnectError("boom", request=httpx.Request("POST", url))


@pytest.mark.asyncio
async def test_send_login_code_requires_resend_configuration():
    service = ResendEmailService()

    with patch("app.services.email_service.settings.resend_api_key", "  "), patch(
        "app.services.email_service.settings.resend_from_email",
        "",
    ):
        with pytest.raises(ValueError) as exc_info:
            await service.send_login_code("user@example.com", "123456")

    assert "not configured" in str(exc_info.value)


@pytest.mark.asyncio
async def test_send_login_code_raises_friendly_error_on_http_failure():
    service = ResendEmailService()
    captured: list[dict] = []

    with patch(
        "app.services.email_service.settings.resend_api_key",
        "resend-key",
    ), patch(
        "app.services.email_service.settings.resend_from_email",
        "noreply@readless.test",
    ), patch(
        "app.services.email_service.httpx.AsyncClient",
        return_value=FakeAsyncClient(SimpleNamespace(status_code=500), captured),
    ):
        with pytest.raises(ValueError) as exc_info:
            await service.send_login_code("user@example.com", "123456")

    assert "failed to send" in str(exc_info.value).lower()
    assert captured[0]["json"]["to"] == ["user@example.com"]


@pytest.mark.asyncio
async def test_send_login_code_posts_expected_payload():
    service = ResendEmailService()
    captured: list[dict] = []

    with patch(
        "app.services.email_service.settings.resend_api_key",
        "resend-key",
    ), patch(
        "app.services.email_service.settings.resend_from_email",
        "noreply@readless.test",
    ), patch(
        "app.services.email_service.httpx.AsyncClient",
        return_value=FakeAsyncClient(SimpleNamespace(status_code=200), captured),
    ):
        await service.send_login_code("user@example.com", "123456")

    request = captured[0]
    assert request["url"] == ResendEmailService.API_URL
    assert request["headers"]["Authorization"] == "Bearer resend-key"
    assert request["json"]["subject"] == "Your Readless verification code"
    assert "123456" in request["json"]["text"]


@pytest.mark.asyncio
async def test_send_verification_email_raises_friendly_error_on_http_failure():
    service = ResendEmailService()
    captured: list[dict] = []

    with patch(
        "app.services.email_service.settings.resend_api_key",
        "resend-key",
    ), patch(
        "app.services.email_service.settings.resend_from_email",
        "noreply@readless.test",
    ), patch(
        "app.services.email_service.httpx.AsyncClient",
        return_value=FakeAsyncClient(SimpleNamespace(status_code=500), captured),
    ):
        with pytest.raises(ValueError) as exc_info:
            await service.send_verification_email("user@example.com", "token-123")

    assert "failed to send verification email" in str(exc_info.value).lower()
    assert captured[0]["json"]["to"] == ["user@example.com"]


@pytest.mark.asyncio
async def test_send_verification_email_posts_expected_payload():
    service = ResendEmailService()
    captured: list[dict] = []

    with patch(
        "app.services.email_service.settings.resend_api_key",
        "resend-key",
    ), patch(
        "app.services.email_service.settings.resend_from_email",
        "noreply@readless.test",
    ), patch(
        "app.services.email_service.httpx.AsyncClient",
        return_value=FakeAsyncClient(SimpleNamespace(status_code=200), captured),
    ):
        await service.send_verification_email("user@example.com", "token-123")

    request = captured[0]
    assert request["url"] == ResendEmailService.API_URL
    assert request["json"]["subject"] == "Verify your Readless email"
    assert "token-123" in request["json"]["text"]
    assert "/api/v1/auth/email/verify?token=token-123" in request["json"]["text"]


@pytest.mark.asyncio
async def test_send_verification_email_raises_friendly_error_on_network_failure():
    service = ResendEmailService()

    with patch(
        "app.services.email_service.settings.resend_api_key",
        "resend-key",
    ), patch(
        "app.services.email_service.settings.resend_from_email",
        "noreply@readless.test",
    ), patch(
        "app.services.email_service.httpx.AsyncClient",
        return_value=ExplodingAsyncClient(),
    ):
        with pytest.raises(ValueError) as exc_info:
            await service.send_verification_email("user@example.com", "token-123")

    assert "failed to send verification email" in str(exc_info.value).lower()

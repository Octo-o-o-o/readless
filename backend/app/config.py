from typing import Literal

from pydantic import Field
from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    """Application settings, read from environment variables / .env file."""

    model_config = SettingsConfigDict(
        env_file=".env",
        env_file_encoding="utf-8",
        case_sensitive=False,
        extra="ignore",
    )

    # --- Database ---
    database_url: str = "postgresql+asyncpg://readless:readless@localhost:5432/readless"

    # --- OpenAI (or compatible APIs like Volcengine, OpenRouter) ---
    openai_api_key: str = ""
    openai_base_url: str | None = None  # Optional: for custom endpoints
    openai_model: str = "gpt-4o"  # Default model for all AI tasks

    # --- Cloudflare R2 ---
    r2_endpoint: str = ""
    r2_access_key: str = ""
    r2_secret_key: str = ""
    r2_bucket: str = "readless"

    # --- ElevenLabs ---
    elevenlabs_api_key: str = ""
    elevenlabs_voice_id: str = "21m00Tcm4TlvDq8ikWAM"  # Default: Rachel

    # --- CORS ---
    cors_origins: list[str] = ["http://localhost:3000"]

    # --- JWT Configuration ---
    jwt_secret_key: str = Field(..., min_length=32)
    jwt_algorithm: str = "HS256"
    access_token_expire_minutes: int = 15
    refresh_token_expire_days: int = 30

    # --- Password Policy ---
    min_password_length: int = 8
    require_password_uppercase: bool = True
    require_password_lowercase: bool = True
    require_password_digit: bool = True

    # --- Apple Configuration ---
    apple_bundle_id: str = "com.readless.app"
    apple_app_store_environment: str = "Production"
    apple_app_apple_id: int | None = None
    apple_enable_online_checks: bool = True
    apple_allow_test_environments: bool = False

    # --- Resend (Email) ---
    resend_api_key: str = ""
    resend_from_email: str = "Readless <noreply@readless.cc>"
    email_login_code_expire_minutes: int = 10
    email_login_code_resend_interval_seconds: int = 30
    public_app_url: str = "https://readless.cc"

    # --- Admin ---
    admin_token: str = Field(..., min_length=32)

    # --- Development ---
    app_env: Literal["development", "test", "staging", "production"] = "development"
    disable_auth: bool = False  # Set to True to disable authentication (dev only)
    allow_disable_auth_in_production: bool = False
    content_processing_concurrency: int = 2
    content_processing_timeout_seconds: int = 1800
    content_job_poll_interval_seconds: float = 1.0
    content_max_text_chars: int = 200_000
    content_max_url_length: int = 2_048
    content_max_upload_bytes: int = 10 * 1024 * 1024
    content_max_remote_fetch_bytes: int = 5 * 1024 * 1024
    allow_local_file_imports: bool = False
    search_max_query_chars: int = 400
    search_retrieve_rate_limit: int = 90
    search_retrieve_rate_window_seconds: int = 60
    search_answer_rate_limit: int = 20
    search_answer_rate_window_seconds: int = 60
    search_llm_timeout_seconds: float = 12.0

    # --- Admin Session ---
    admin_session_https_only: bool = True
    admin_session_same_site: Literal["lax", "strict", "none"] = "lax"
    admin_session_max_age_seconds: int = 3600


settings = Settings()

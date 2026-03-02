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

    # --- Clerk ---
    clerk_secret_key: str = ""
    clerk_domain: str = ""  # e.g. "your-app.clerk.accounts.dev"

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

    # --- Resend (Email) ---
    resend_api_key: str = ""
    resend_from_email: str = "Readless <noreply@readless.cc>"

    # --- Admin ---
    admin_token: str = Field(..., min_length=32)

    # --- Development ---
    disable_auth: bool = False  # Set to True to disable authentication (dev only)


settings = Settings()

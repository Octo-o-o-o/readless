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

    # --- Development ---
    disable_auth: bool = False  # Set to True to disable Clerk authentication (dev only)


settings = Settings()

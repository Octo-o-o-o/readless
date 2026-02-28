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

    # --- Anthropic ---
    anthropic_api_key: str = ""

    # --- Clerk ---
    clerk_secret_key: str = ""

    # --- Cloudflare R2 ---
    r2_endpoint: str = ""
    r2_access_key: str = ""
    r2_secret_key: str = ""
    r2_bucket: str = "readless"

    # --- ElevenLabs ---
    elevenlabs_api_key: str = ""

    # --- CORS ---
    cors_origins: list[str] = ["http://localhost:3000"]


settings = Settings()

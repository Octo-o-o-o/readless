"""Podcast generation service: script generation via OpenAI-compatible API, audio via ElevenLabs."""

import json
import uuid

import openai
import httpx
from sqlalchemy.ext.asyncio import AsyncSession

from app.config import settings
from app.models.content import Content
from app.models.podcast import Podcast
from app.services.storage import StorageService


class PodcastService:
    def __init__(self):
        self._client: openai.OpenAI | None = None
        self._storage: StorageService | None = None

    @property
    def client(self) -> openai.OpenAI:
        """Lazily create the OpenAI client on first access."""
        if self._client is None:
            self._client = openai.OpenAI(
                api_key=settings.openai_api_key,
                base_url=settings.openai_base_url,
            )
        return self._client

    @property
    def storage(self) -> StorageService:
        """Lazily create the StorageService on first access."""
        if self._storage is None:
            self._storage = StorageService()
        return self._storage

    async def generate(self, content: Content, db: AsyncSession) -> Podcast:
        """Generate a full podcast: script, audio, and upload to R2."""
        podcast_id = str(uuid.uuid4())
        podcast = Podcast(id=podcast_id, content_id=content.id, status="generating")
        db.add(podcast)
        await db.commit()

        try:
            # Step 1: Generate podcast script from outline
            script = await self._generate_script(content)

            # Step 2: Generate audio via ElevenLabs Text to Dialogue
            audio_bytes = await self._generate_audio(script["dialogue"])

            # Step 3: Upload to R2
            key = f"podcasts/{content.user_id}/{podcast_id}.mp3"
            audio_url = self.storage.upload_audio(key, audio_bytes)

            # Step 4: Update podcast record
            podcast.audio_url = audio_url
            podcast.script = script
            podcast.chapters = script.get("chapters", [])
            podcast.status = "ready"

        except Exception as e:
            podcast.status = "failed"
            podcast.script = {"error": str(e)}

        await db.commit()
        return podcast

    async def _generate_script(self, content: Content) -> dict:
        """Use AI to generate a conversational podcast script from content."""
        outline_text = json.dumps(content.l1_outline, ensure_ascii=False)
        message = self.client.chat.completions.create(
            model=settings.openai_model,
            max_tokens=3000,
            messages=[
                {
                    "role": "user",
                    "content": f"""Create a podcast dialogue script for two hosts discussing this content.

TITLE: {content.title}
SUMMARY: {content.l0_summary}
OUTLINE:
{outline_text}

Requirements:
1. Two speakers: Host A (introduces topics) and Host B (provides analysis)
2. Natural conversational tone, NOT a dry reading
3. Cover each outline point as a separate chapter
4. Include an intro and outro
5. Total length: ~3-5 minutes when spoken

Return JSON:
{{
  "dialogue": "Host A: Welcome to... Host B: Thanks...",
  "chapters": [
    {{"title": "Introduction", "outline_point_index": null}},
    {{"title": "Chapter title matching outline point", "outline_point_index": 0}},
    ...
  ]
}}
JSON only.""",
                }
            ],
        )
        raw = message.choices[0].message.content
        if raw.startswith("```"):
            raw = raw.split("\n", 1)[1].rsplit("```", 1)[0]
        return json.loads(raw)

    async def _generate_audio(self, dialogue_text: str) -> bytes:
        """Use ElevenLabs Text to Dialogue API to convert script to audio."""
        async with httpx.AsyncClient() as client:
            resp = await client.post(
                "https://api.elevenlabs.io/v1/text-to-dialogue",
                headers={
                    "xi-api-key": settings.elevenlabs_api_key,
                    "Content-Type": "application/json",
                },
                json={"text": dialogue_text},
                timeout=120,
            )
            resp.raise_for_status()
            return resp.content

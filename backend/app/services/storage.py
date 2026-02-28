"""Storage service for uploading and retrieving audio files from Cloudflare R2."""

import boto3

from app.config import settings


class StorageService:
    def __init__(self):
        self._s3 = None

    @property
    def s3(self):
        """Lazily create the S3 client on first access."""
        if self._s3 is None:
            self._s3 = boto3.client(
                "s3",
                endpoint_url=settings.r2_endpoint,
                aws_access_key_id=settings.r2_access_key,
                aws_secret_access_key=settings.r2_secret_key,
            )
        return self._s3

    @property
    def bucket(self) -> str:
        return settings.r2_bucket

    def upload_audio(self, key: str, data: bytes) -> str:
        """Upload audio bytes to R2 and return the public URL."""
        self.s3.put_object(
            Bucket=self.bucket, Key=key, Body=data, ContentType="audio/mpeg"
        )
        return f"{settings.r2_endpoint}/{self.bucket}/{key}"

    def get_presigned_url(self, key: str, expires_in: int = 3600) -> str:
        """Generate a presigned URL for downloading audio."""
        return self.s3.generate_presigned_url(
            "get_object",
            Params={"Bucket": self.bucket, "Key": key},
            ExpiresIn=expires_in,
        )

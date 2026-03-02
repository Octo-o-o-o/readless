"""SQLAdmin configuration for Readless admin dashboard."""

from sqladmin import Admin, ModelView
from sqladmin.authentication import AuthenticationBackend
from starlette.requests import Request
from starlette.responses import RedirectResponse

from app.config import settings
from app.database import get_engine
from app.models import (
    Content,
    PasswordResetToken,
    RefreshToken,
    User,
    UserTag,
)


class AdminAuth(AuthenticationBackend):
    """Simple token-based authentication for admin panel.

    Username can be anything, password must be the ADMIN_TOKEN from .env
    """

    async def login(self, request: Request) -> bool:
        """Authenticate admin user with token.

        The password field should contain the ADMIN_TOKEN.
        Username can be anything (e.g., "admin").
        """
        form = await request.form()
        password = form.get("password")

        # Password must match ADMIN_TOKEN
        if password == settings.admin_token:
            request.session.update({"authenticated": True})
            return True

        return False

    async def logout(self, request: Request) -> bool:
        """Logout admin user."""
        request.session.clear()
        return True

    async def authenticate(self, request: Request) -> bool:
        """Check if user is authenticated."""
        return request.session.get("authenticated", False)


class UserAdmin(ModelView, model=User):
    """Admin view for User model."""

    name = "User"
    name_plural = "Users"
    icon = "fa-solid fa-user"

    # List view configuration
    column_list = [
        User.id,
        User.email,
        User.apple_id,
        User.subscription_tier,
        User.trial_expires_at,
        User.subscription_expires_at,
        User.email_verified,
        User.created_at,
        User.last_login_at,
    ]

    column_searchable_list = [User.email, User.apple_id]
    column_sortable_list = [
        User.email,
        User.subscription_tier,
        User.created_at,
        User.last_login_at,
    ]
    column_default_sort = [(User.created_at, True)]  # Newest first

    # Detail view configuration (exclude sensitive fields)
    column_details_exclude_list = [User.password_hash, User.apple_receipt_data]

    # Editable fields
    form_columns = [
        User.email,
        User.apple_id,
        User.subscription_tier,
        User.trial_expires_at,
        User.subscription_expires_at,
        User.email_verified,
    ]

    # Pagination
    page_size = 50
    page_size_options = [25, 50, 100, 200]


class ContentAdmin(ModelView, model=Content):
    """Admin view for Content model (read-only for debugging)."""

    name = "Content"
    name_plural = "Contents"
    icon = "fa-solid fa-file-lines"

    # List view configuration
    column_list = [
        Content.id,
        Content.user_id,
        Content.title,
        Content.source_type,
        Content.status,
        Content.created_at,
    ]

    column_searchable_list = [Content.title, Content.user_id]
    column_sortable_list = [Content.user_id, Content.created_at, Content.status]
    column_default_sort = [(Content.created_at, True)]  # Newest first

    # Detail view - show all fields except large text fields
    column_details_list = [
        Content.id,
        Content.user_id,
        Content.title,
        Content.source_url,
        Content.source_type,
        Content.source_app_name,
        Content.source_app_bundle_id,
        Content.channel,
        Content.l0_summary,
        Content.keywords,
        Content.source_language,
        Content.status,
        Content.created_at,
        Content.updated_at,
    ]

    # Make read-only (for debugging purposes only)
    can_create = False
    can_edit = False
    can_delete = False

    # Pagination
    page_size = 50
    page_size_options = [25, 50, 100, 200]


class RefreshTokenAdmin(ModelView, model=RefreshToken):
    """Admin view for RefreshToken model."""

    name = "Refresh Token"
    name_plural = "Refresh Tokens"
    icon = "fa-solid fa-key"

    # List view configuration
    column_list = [
        RefreshToken.id,
        RefreshToken.user_id,
        RefreshToken.device_name,
        RefreshToken.expires_at,
        RefreshToken.created_at,
        RefreshToken.last_used_at,
    ]

    column_searchable_list = [RefreshToken.user_id, RefreshToken.device_name]
    column_sortable_list = [
        RefreshToken.user_id,
        RefreshToken.expires_at,
        RefreshToken.created_at,
        RefreshToken.last_used_at,
    ]
    column_default_sort = [(RefreshToken.created_at, True)]  # Newest first

    # Detail view
    column_details_list = [
        RefreshToken.id,
        RefreshToken.user_id,
        RefreshToken.token,
        RefreshToken.device_name,
        RefreshToken.device_id,
        RefreshToken.expires_at,
        RefreshToken.created_at,
        RefreshToken.last_used_at,
    ]

    # Can delete (revoke) tokens
    can_create = False
    can_edit = False
    can_delete = True

    # Pagination
    page_size = 50
    page_size_options = [25, 50, 100, 200]


class PasswordResetTokenAdmin(ModelView, model=PasswordResetToken):
    """Admin view for PasswordResetToken model."""

    name = "Password Reset Token"
    name_plural = "Password Reset Tokens"
    icon = "fa-solid fa-lock-open"

    # List view configuration
    column_list = [
        PasswordResetToken.id,
        PasswordResetToken.user_id,
        PasswordResetToken.expires_at,
        PasswordResetToken.created_at,
        PasswordResetToken.used_at,
    ]

    column_searchable_list = [PasswordResetToken.user_id]
    column_sortable_list = [
        PasswordResetToken.user_id,
        PasswordResetToken.expires_at,
        PasswordResetToken.created_at,
    ]
    column_default_sort = [(PasswordResetToken.created_at, True)]  # Newest first

    # Detail view
    column_details_list = [
        PasswordResetToken.id,
        PasswordResetToken.user_id,
        PasswordResetToken.token,
        PasswordResetToken.expires_at,
        PasswordResetToken.created_at,
        PasswordResetToken.used_at,
    ]

    # Can delete expired tokens
    can_create = False
    can_edit = False
    can_delete = True

    # Pagination
    page_size = 50
    page_size_options = [25, 50, 100, 200]


class UserTagAdmin(ModelView, model=UserTag):
    """Admin view for UserTag model."""

    name = "User Tag"
    name_plural = "User Tags"
    icon = "fa-solid fa-tags"

    # List view configuration
    column_list = [
        UserTag.id,
        UserTag.user_id,
        UserTag.tag_name,
        UserTag.created_at,
        UserTag.deleted_at,
    ]

    column_searchable_list = [UserTag.user_id, UserTag.tag_name]
    column_sortable_list = [
        UserTag.user_id,
        UserTag.tag_name,
        UserTag.created_at,
    ]
    column_default_sort = [(UserTag.created_at, True)]  # Newest first

    # Read-only (tags are managed via API)
    can_create = False
    can_edit = False
    can_delete = False

    # Pagination
    page_size = 50
    page_size_options = [25, 50, 100, 200]


def create_admin(app) -> Admin:
    """Create and configure SQLAdmin instance."""
    authentication_backend = AdminAuth(secret_key=settings.jwt_secret_key)

    admin = Admin(
        app=app,
        engine=get_engine(),
        title="Readless Admin",
        logo_url=None,
        authentication_backend=authentication_backend,
    )

    # Register admin views
    admin.add_view(UserAdmin)
    admin.add_view(ContentAdmin)
    admin.add_view(RefreshTokenAdmin)
    admin.add_view(PasswordResetTokenAdmin)
    admin.add_view(UserTagAdmin)

    return admin

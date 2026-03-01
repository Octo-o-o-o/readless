# User Tag System Design

**Date:** 2026-03-01
**Status:** Approved
**Author:** Claude Code

## Overview

This design document describes the implementation of a customizable user tag system for Readless. Users can build their own tag library, and AI will automatically select relevant tags when generating content summaries. Tags enable content organization and filtering through the sidebar.

## Requirements

### Core Functionality
1. **Tag Library Management**
   - Users start with an empty tag library
   - Users can manually add tags to their library
   - Tags are displayed in the sidebar under "Knowledge" section
   - Users can delete tags from their library (logical deletion)

2. **AI Tag Selection**
   - When generating summaries, AI receives the user's tag library
   - AI selects 0-N most relevant tags from the library
   - If no tags are relevant, AI returns empty array
   - Tags are per-user and completely isolated

3. **Content Tag Management**
   - Users can add/remove tags on individual content items
   - Adding a new tag (not in library) automatically creates it in the library
   - Content is categorized by tags

4. **Tag Filtering**
   - Clicking a tag in the sidebar filters content by that tag
   - Each tag shows the content count

### User Experience
- Tags are added inline when viewing content (no separate settings page)
- Tags are plain text (no colors/icons in MVP)
- Deleting a tag removes it from all content

## Architecture Decision

We chose **Relational Table Design (Many-to-Many)** over simpler array-based approaches for these reasons:

### Advantages
- ✅ Normalized database design
- ✅ Efficient tag deletion (simple CASCADE)
- ✅ Easy to add tag metadata later (colors, icons, usage stats)
- ✅ Better query performance for filtering by tag
- ✅ Cleaner data model for future features

### Trade-offs
- More complex than PostgreSQL ARRAY approach
- Requires JOIN operations for tag queries
- Higher initial implementation cost

This is the right choice for long-term maintainability and extensibility.

## Data Model

### Database Schema

#### Table: `user_tags`
Stores each user's tag library with logical deletion support.

```sql
CREATE TABLE user_tags (
    id SERIAL PRIMARY KEY,
    user_id VARCHAR(100) NOT NULL,
    tag_name VARCHAR(50) NOT NULL,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW() NOT NULL,
    deleted_at TIMESTAMP WITH TIME ZONE NULL,

    CONSTRAINT uq_user_tag UNIQUE (user_id, tag_name)
);

CREATE INDEX idx_user_tags_user_id ON user_tags(user_id)
    WHERE deleted_at IS NULL;
CREATE INDEX idx_user_tags_deleted_at ON user_tags(deleted_at);
```

**Logical Deletion:** Setting `deleted_at` allows tag restoration and maintains historical data.

#### Table: `content_tags`
Many-to-many relationship between content and tags.

```sql
CREATE TABLE content_tags (
    content_id VARCHAR(36) NOT NULL REFERENCES contents(id) ON DELETE CASCADE,
    tag_id INTEGER NOT NULL REFERENCES user_tags(id) ON DELETE CASCADE,
    user_id VARCHAR(100) NOT NULL,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW() NOT NULL,

    PRIMARY KEY (content_id, tag_id)
);

CREATE INDEX idx_content_tags_tag_id ON content_tags(tag_id);
CREATE INDEX idx_content_tags_content_id ON content_tags(content_id);
CREATE INDEX idx_content_tags_user_id ON content_tags(user_id);
```

**Redundant `user_id`:** Improves query performance for filtering by user.

#### Table: `contents` (Modified)
Remove existing `tags` ARRAY column and its GIN index.

```sql
ALTER TABLE contents DROP COLUMN tags;
DROP INDEX IF EXISTS ix_contents_tags;
```

### SQLAlchemy ORM Models

#### `backend/app/models/user_tag.py`
```python
class UserTag(Base):
    __tablename__ = "user_tags"

    id: Mapped[int] = mapped_column(Integer, primary_key=True, autoincrement=True)
    user_id: Mapped[str] = mapped_column(String(100), nullable=False)
    tag_name: Mapped[str] = mapped_column(String(50), nullable=False)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.now())
    deleted_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True), nullable=True)
```

#### `backend/app/models/content_tag.py`
```python
class ContentTag(Base):
    __tablename__ = "content_tags"

    content_id: Mapped[str] = mapped_column(String(36), ForeignKey("contents.id", ondelete="CASCADE"), primary_key=True)
    tag_id: Mapped[int] = mapped_column(Integer, ForeignKey("user_tags.id", ondelete="CASCADE"), primary_key=True)
    user_id: Mapped[str] = mapped_column(String(100), nullable=False)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.now())
```

## API Design

### New Endpoints (`/api/v1/tags`)

#### `GET /api/v1/tags`
List user's tag library with content count.

**Response:**
```json
[
  {
    "id": 1,
    "tag_name": "技术",
    "content_count": 15,
    "created_at": "2026-03-01T12:00:00Z"
  }
]
```

#### `POST /api/v1/tags`
Create a new tag in user's library.

**Request:**
```json
{
  "tag_name": "投资"
}
```

**Response:** Same as `UserTagResponse`

**Behavior:** If tag was soft-deleted, it will be restored (set `deleted_at = NULL`).

#### `DELETE /api/v1/tags/{tag_id}`
Soft delete a tag and remove from all content.

**Behavior:**
1. Set `user_tags.deleted_at = NOW()`
2. Delete all `content_tags` relationships (CASCADE)

#### `GET /api/v1/tags/content/{content_id}/tags`
Get tags for a specific content item.

**Response:**
```json
["技术", "学习"]
```

#### `PUT /api/v1/tags/content/{content_id}/tags`
Update tags for a content item (auto-create missing tags).

**Request:**
```json
{
  "tag_names": ["技术", "学习", "投资"]
}
```

**Behavior:**
1. Remove all existing tags for this content
2. For each tag name:
   - Check if exists in user's library
   - If not, create new tag in library
   - Create `content_tags` relationship

#### `GET /api/v1/tags/{tag_id}/contents` (New)
Get all content items with this tag.

**Response:** Array of `ContentResponse` objects

### Modified Endpoints

#### `GET /api/v1/content/{content_id}`
Response now includes `tags` array (fetched via JOIN).

**Implementation:**
```python
# Join user_tags to get tag names
stmt = (
    select(UserTag.tag_name)
    .join(ContentTag, UserTag.id == ContentTag.tag_id)
    .where(
        ContentTag.content_id == content_id,
        UserTag.deleted_at.is_(None)
    )
)
tags = [row[0] for row in await db.execute(stmt)]
```

## AI Integration

### Summarization Service Changes

**Before:**
```python
# AI prompt simply said: "generate 3-5 topic tags"
```

**After:**
```python
async def generate_summary(full_text: str, paragraphs: list[str], user_id: str, db: AsyncSession):
    # 1. Fetch user's tag library
    stmt = select(UserTag.tag_name).where(
        UserTag.user_id == user_id,
        UserTag.deleted_at.is_(None)
    )
    available_tags = [row[0] for row in await db.execute(stmt)]

    # 2. Build prompt with tag library
    if available_tags:
        tag_instruction = f"""
- "tags": Select 0-3 most relevant tags from user's library: {available_tags}
  If none are relevant, return empty array.
"""
    else:
        tag_instruction = """
- "tags": Empty array (user has no tag library yet).
"""

    # 3. Call OpenAI with updated prompt
    system_prompt = f"""You are a professional content analyst...
{tag_instruction}
Return ONLY JSON object."""
```

### Pipeline Service Changes

After AI generates tags, save them to `content_tags` table:

```python
# Get tag IDs from user's library
for tag_name in summary_result.tags:
    stmt = select(UserTag.id).where(
        UserTag.user_id == user_id,
        UserTag.tag_name == tag_name,
        UserTag.deleted_at.is_(None)
    )
    tag_id = (await db.execute(stmt)).scalar_one_or_none()

    if tag_id:
        content_tag = ContentTag(
            content_id=content_id,
            tag_id=tag_id,
            user_id=user_id
        )
        db.add(content_tag)
```

## Frontend Design (macOS)

### New Components

#### `Core/Models/Tag.swift`
```swift
public struct UserTag: Identifiable, Codable, Sendable {
    public let id: Int
    public var tagName: String
    public var contentCount: Int
    public let createdAt: Date
}
```

#### `Networking/APIClient.swift` (Extensions)
```swift
func fetchUserTags() async throws -> [UserTag]
func createTag(name: String) async throws -> UserTag
func deleteTag(id: Int) async throws
func updateContentTags(contentId: String, tags: [String]) async throws
func fetchContentsByTag(tagId: Int) async throws -> [Content]
```

#### `App/Services/TagManager.swift`
```swift
@Observable
final class TagManager {
    var userTags: [UserTag] = []
    var selectedTagId: Int? = nil

    func loadUserTags() async
    func createTag(name: String) async throws
    func deleteTag(id: Int) async throws
    func selectTag(_ tagId: Int?)
}
```

### UI Changes

#### Sidebar - Knowledge Section
```swift
Section("Knowledge") {
    ForEach(tagManager.userTags) { tag in
        Button {
            tagManager.selectTag(tag.id)
            Task {
                await contentManager.filterByTag(tagId: tag.id)
            }
        } label: {
            HStack {
                Label(tag.tagName, systemImage: "tag")
                Spacer()
                Text("\(tag.contentCount)")
                    .foregroundStyle(.secondary)
            }
        }
        .contextMenu {
            Button("Delete Tag", role: .destructive) {
                Task { try? await tagManager.deleteTag(id: tag.id) }
            }
        }
    }
}
```

#### ReaderView - Tag Display & Editing
```swift
TagsView(
    tags: content.tags,
    availableTags: tagManager.userTags.map(\.tagName),
    onAdd: { tagName in await addTag(tagName) },
    onRemove: { tagName in await removeTag(tagName) }
)
```

Components:
- `TagsView`: Display tags with add/remove buttons
- `TagChip`: Individual tag with remove button
- `TagPickerView`: Popover to select existing tag or create new

## Data Migration

### Alembic Migration Script

**Migration:** `xxxx_add_tag_system.py`

```python
def upgrade():
    # 1. Create user_tags and content_tags tables
    # 2. Migrate existing tags from contents.tags array:
    op.execute("""
        -- Populate user_tags from existing content tags
        INSERT INTO user_tags (user_id, tag_name)
        SELECT DISTINCT user_id, unnest(tags) as tag_name
        FROM contents
        WHERE tags IS NOT NULL AND array_length(tags, 1) > 0
        ON CONFLICT (user_id, tag_name) DO NOTHING;

        -- Populate content_tags relationships
        INSERT INTO content_tags (content_id, tag_id, user_id)
        SELECT c.id, ut.id, c.user_id
        FROM contents c
        CROSS JOIN LATERAL unnest(c.tags) as tag_name
        JOIN user_tags ut ON ut.user_id = c.user_id
                         AND ut.tag_name = tag_name
        WHERE c.tags IS NOT NULL;
    """)
    # 3. Drop contents.tags column and index
```

**Downgrade:** Restore `tags` array column and migrate data back.

## Data Flow Examples

### Example 1: Import New Content

```
User imports article
    ↓
POST /api/v1/content
    ↓
ProcessingPipeline.process_content()
    ↓
Extract text → Generate summary
    ↓
SummarizationService.generate_summary(user_id, db)
  - Query: SELECT tag_name FROM user_tags WHERE user_id=X AND deleted_at IS NULL
  - Result: ["工作", "学习", "技术"]
  - Prompt: "Select 0-3 tags from: [工作, 学习, 技术]"
  - AI returns: {"tags": ["技术", "学习"], ...}
    ↓
Save summary & create content_tags relationships
  - For each tag: INSERT INTO content_tags (content_id, tag_id, user_id)
    ↓
Return ContentResponse with tags: ["技术", "学习"]
    ↓
Frontend displays content with tags
```

### Example 2: Add Tag to Content

```
User viewing content, adds tag "投资"
    ↓
TagsView.onAdd("投资")
    ↓
PUT /api/v1/tags/content/{id}/tags
  body: {tag_names: ["技术", "学习", "投资"]}
    ↓
Backend:
  - Check if "投资" exists in user_tags
  - Not found → INSERT INTO user_tags (user_id, tag_name) VALUES (X, '投资')
  - DELETE FROM content_tags WHERE content_id=Y
  - INSERT INTO content_tags for all three tags
    ↓
Return success
    ↓
Frontend refreshes tag display
    ↓
Sidebar "Knowledge" section now shows "投资" tag
```

### Example 3: Filter by Tag

```
User clicks "技术" tag in sidebar
    ↓
TagManager.selectTag(tagId: 5)
    ↓
ContentManager.filterByTag(tagId: 5)
    ↓
GET /api/v1/tags/5/contents
    ↓
Backend:
  SELECT c.* FROM contents c
  JOIN content_tags ct ON c.id = ct.content_id
  WHERE ct.tag_id = 5 AND ct.user_id = X
    ↓
Return filtered content list
    ↓
ContentListView displays only content tagged "技术"
```

### Example 4: Delete Tag

```
User right-clicks "投资" tag, selects "Delete Tag"
    ↓
TagManager.deleteTag(id: 3)
    ↓
DELETE /api/v1/tags/3
    ↓
Backend:
  - UPDATE user_tags SET deleted_at=NOW() WHERE id=3
  - DELETE FROM content_tags WHERE tag_id=3 (CASCADE)
    ↓
Return success
    ↓
Frontend removes tag from sidebar
    ↓
All content previously tagged "投资" no longer has that tag
```

## Testing Strategy

### Backend Tests

**Unit Tests:**
- `test_user_tag_crud.py`: Create, read, update, delete tags
- `test_content_tag_assignment.py`: Assign/remove tags from content
- `test_tag_soft_delete.py`: Verify logical deletion behavior
- `test_ai_tag_selection.py`: Mock AI tag selection with user library

**Integration Tests:**
- `test_tag_migration.py`: Verify data migration from array to relational
- `test_tag_filtering.py`: Query content by tag
- `test_tag_isolation.py`: Verify user tag isolation

### Frontend Tests

**Unit Tests:**
- `TagManagerTests.swift`: Test tag CRUD operations
- `TagsViewTests.swift`: Test tag display and editing UI

**Integration Tests:**
- Test tag creation flow (add tag → appears in sidebar)
- Test tag deletion flow (delete → removed from content)
- Test filtering flow (click tag → filter content)

## Performance Considerations

### Query Optimization

1. **Tag Library Fetch:** Cached in frontend `TagManager`
2. **Content Tags:** JOINed in single query when fetching content
3. **Tag Filtering:** Uses indexed `content_tags.tag_id`

### Indexing Strategy

- `user_tags`: Partial index on `(user_id)` WHERE `deleted_at IS NULL`
- `content_tags`: Indexes on `tag_id`, `content_id`, `user_id`
- PostgreSQL query planner will use appropriate index based on query

### Scalability

- Expected: <100 tags per user, <1000 contents per user
- Current design handles 10x these numbers efficiently
- For extreme scale (100K+ contents), consider caching tag counts

## Future Enhancements (Out of Scope)

These features are NOT included in this design but could be added later:

1. **Tag Visual Customization**
   - Colors, icons, emojis
   - Requires `color` column in `user_tags`

2. **Tag Hierarchy**
   - Parent-child relationships (e.g., "技术" → "前端" → "React")
   - Requires `parent_tag_id` column

3. **Tag Suggestions**
   - AI suggests new tags based on content corpus
   - Requires analysis of untagged content

4. **Tag Analytics**
   - Most used tags, trending tags
   - Requires aggregation queries

5. **Tag Aliases**
   - Map multiple names to same tag (e.g., "工作" = "职场")
   - Requires `tag_aliases` table

## Risks & Mitigations

### Risk: Data Migration Failure
**Mitigation:**
- Write migration with transaction rollback
- Test on staging database first
- Keep backup before migration

### Risk: Performance Degradation
**Mitigation:**
- Indexes on all JOIN columns
- Monitor query performance in production
- Add caching if needed

### Risk: User Confusion (No Tags)
**Mitigation:**
- Show empty state with "Add your first tag" prompt
- Add tooltip explaining tag system

## Conclusion

This design provides a solid foundation for user-customizable tags in Readless. The relational design offers flexibility for future enhancements while maintaining good performance for the expected scale. The implementation is phased to minimize risk and allow for iterative improvements.

**Next Steps:**
1. Create implementation plan with task breakdown
2. Implement backend (database, API, AI integration)
3. Implement frontend (UI, tag management)
4. Test thoroughly
5. Deploy with data migration

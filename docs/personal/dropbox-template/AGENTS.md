# Books library instructions — proposed format v1

This file is a template for the chosen Dropbox library root. Agents must be explicitly
directed to read it before adding or changing a book. The application must also
validate metadata; the file's presence alone does not enforce these rules.

## Layout

```text
Books/
  AGENTS.md
  books/
    <book-uuid>/
      metadata.json
      audio.mp3
      cover.jpg
```

- One directory per book, named with a permanent lowercase UUID.
- One audio file per book in v1: `audio.mp3`, `audio.m4a`, `audio.m4b`, or
  `audio.mp4`. Preserve the source container and encoding; do not merely change
  an extension or transcode the audio to make filenames uniform.
- For an MP4 container, verify that the file contains a playable audio track.
- Metadata is UTF-8 JSON matching `book.schema.json`; its `id` equals the directory UUID.
- Optional artwork is `cover.jpg` or `cover.png`.
- Unknown authors/narrators are empty arrays; unknown language is null. Do not
  invent authors, language, duration, cover, checksums, or other book information.

## Adding a book

1. Read this file and the schema.
2. Inspect existing IDs and available audio hashes to avoid duplicate books.
   Do not merge different editions solely because their titles match.
3. Assign a new UUID only to a new book. Keep it when renaming or moving a book.
4. Copy into a temporary staging directory, inspect the actual audio, and generate
   metadata. Record the original filename when known.
5. Validate metadata, file existence, playable audio, and the ID/directory match.
6. Publish the completed book directory. Do not expose incomplete audio as ready.
7. Report the new book ID and any missing optional information.

Existing loose files require an explicit migration plan before being moved or renamed.
Do not delete, overwrite, move, or rename existing user files as a side effect of
preparing this template.

## Keeping personal records

The app's journal, listening positions, sleep anchors, and favorite bookmarks use the
book UUID. Removing a device download must preserve them. A replacement audio edition
requires an explicit policy for old time-based bookmarks.

Do not put OAuth tokens, Apple credentials, or signing material in this directory.
Personal backups belong in a separately chosen backup location, not in audio metadata.
A backup and export format will be versioned independently of this metadata schema.

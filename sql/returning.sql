-- RETURNING queries: INSERT / UPDATE / DELETE that decode their result rows
-- via queryDecode (instead of exec). Cardinality drives the shape.
CREATE TABLE notes (
    id    INTEGER PRIMARY KEY,
    title TEXT    NOT NULL,
    body  TEXT
);


-- Full projection -> reuses the Note Model; :one -> Maybe Note.
-- name: CreateNote :one
INSERT INTO notes (title, body)
VALUES (@title, @body)
RETURNING id, title, body;


-- Single RETURNING column -> Maybe Int scalar (the freshly-assigned id).
-- name: CreateNoteId :scalar
INSERT INTO notes (title, body)
VALUES (@title, @body)
RETURNING id;


-- UPDATE ... RETURNING a partial projection -> a Row; :one -> Maybe Row.
-- name: TouchNote :one
UPDATE notes
SET title = @title
WHERE id = @id
RETURNING id, title;


-- UPDATE affecting many rows -> :many -> List Row.
-- name: BumpTitles :many
UPDATE notes
SET title = @title
WHERE id > @min
RETURNING id, title;


-- DELETE ... RETURNING -> scalar id of the removed row.
-- name: DeleteNote :scalar
DELETE FROM notes
WHERE id = @id
RETURNING id;

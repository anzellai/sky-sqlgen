-- DEFAULT-omittable INSERT: opt-in per statement via `-- @omit col, ...`.
-- Listed columns become SqlField-typed params (the caller picks SetField v /
-- OmitField). The whole INSERT then emits a runtime builder with literal
-- column names + a placeholder count; omitted columns fall back to the DB
-- DEFAULT. A NOT NULL column without a DEFAULT cannot be omitted (loud-fail).
CREATE TABLE items (
    id     INTEGER PRIMARY KEY,
    name   TEXT    NOT NULL,
    status TEXT    NOT NULL DEFAULT 'pending',
    note   TEXT
);


-- name: CreateItem :execrows
-- @omit status, note
INSERT INTO items (name, status, note)
VALUES (@name, @status, @note);


-- @omit + RETURNING: full projection reuses the Item Model; :one -> Maybe Item.
-- The returned row reflects DB-applied defaults for omitted columns.
-- name: CreateItemReturning :one
-- @omit status, note
INSERT INTO items (name, status, note)
VALUES (@name, @status, @note)
RETURNING id, name, status, note;


-- @omit + RETURNING a single column -> :scalar -> Maybe Int.
-- name: CreateItemId :scalar
-- @omit status, note
INSERT INTO items (name, status, note)
VALUES (@name, @status, @note)
RETURNING id;

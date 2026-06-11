-- Auto-naming demo: NOT ONE statement carries a `-- name:` annotation.
-- sky-sqlgen derives verb + entity + By<cols> + a cardinality from the
-- catalog. PRIMARY KEY / UNIQUE equality => :one; otherwise :many.

CREATE TABLE users (
    id         INTEGER PRIMARY KEY,
    name       TEXT    NOT NULL,
    email      TEXT    NOT NULL UNIQUE,
    active     BOOLEAN NOT NULL DEFAULT 1,
    created_at TEXT    NOT NULL
);

-- id is the PRIMARY KEY -> getUserById :one (full projection reuses User).
SELECT id, name, email, active, created_at FROM users WHERE id = @id;

-- Same derived name (getUserById) but a partial projection -> the clash
-- integer-suffixes to getUserById1 :one (its own GetUserById1Row).
SELECT id, name FROM users WHERE id = @id;

-- email is UNIQUE -> getUserByEmail :one.
SELECT id, name, email, active, created_at FROM users WHERE email = @email;

-- `active` is neither PK nor UNIQUE -> listUsersByActive :many.
SELECT id, name, email FROM users WHERE active = @active ORDER BY created_at DESC;

-- No WHERE -> listUsers :many (full projection reuses User).
SELECT id, name, email, active, created_at FROM users;

-- INSERT -> createUser; no RETURNING -> :execrows.
INSERT INTO users (name, email, active, created_at)
VALUES (@name, @email, @active, @created_at);

-- UPDATE ... WHERE id -> updateUserById :execrows.
UPDATE users SET name = @name, email = @email WHERE id = @id;

-- DELETE ... WHERE id -> deleteUserById :execrows.
DELETE FROM users WHERE id = @id;

-- Off-subset (a CTE) the tool can't handle -> SKIPPED with a file:line
-- warning; every statement above still generates and the run exits 0.
WITH recent AS (SELECT id FROM users ORDER BY created_at DESC)
SELECT id FROM recent;

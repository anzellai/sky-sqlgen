-- Schema (auto-detected; no name: annotation needed)
CREATE TABLE users (
    id         INTEGER PRIMARY KEY,
    name       TEXT    NOT NULL,
    email      TEXT    NOT NULL UNIQUE,
    bio        TEXT,
    age        INTEGER,
    active     BOOLEAN NOT NULL DEFAULT 1,
    created_at TEXT    NOT NULL
);

-- name: GetUser :one
SELECT id, name, email, bio, age, active, created_at
FROM users
WHERE id = @id;

-- name: ListActiveUsers :many
SELECT id, name, email
FROM users
WHERE active = @active
ORDER BY created_at DESC;

-- name: CreateUser :exec
INSERT INTO users (name, email, bio, age, active, created_at)
VALUES (@name, @email, @bio, @age, @active, @created_at);

-- name: DeleteUser :execrows
DELETE FROM users WHERE id = @id;

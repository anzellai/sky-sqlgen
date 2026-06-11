-- Schema (auto-detected; feeds the catalog)
CREATE TABLE users (
    id    INTEGER PRIMARY KEY,
    name  TEXT    NOT NULL,
    email TEXT    NOT NULL UNIQUE
);

CREATE TABLE profiles (
    id       INTEGER PRIMARY KEY,
    user_id  INTEGER NOT NULL,
    bio      TEXT    NOT NULL,
    website  TEXT
);

-- LEFT JOIN: every right-side column is demoted to Maybe, even though the
-- catalog marks `bio` NOT NULL and `id` PRIMARY KEY. A missing profile row
-- yields SQL NULL for those columns; the runtime decodes them to Nothing.
-- name: ListUsersWithBio :many
SELECT u.id AS user_id, u.name, u.email, p.bio, p.website
FROM users u
LEFT JOIN profiles p ON p.user_id = u.id
ORDER BY u.id;

-- INNER JOIN: no demotion. `bio` stays non-null because an inner join only
-- returns rows where the profile exists.
-- name: ListUsersWithBioInner :many
SELECT u.id AS user_id, u.name, p.bio
FROM users u
INNER JOIN profiles p ON p.user_id = u.id
ORDER BY u.id;

-- LEFT JOIN with a param typed via the ON / WHERE adjacency across the scope.
-- name: GetUserProfile :one
SELECT u.id AS user_id, u.name, p.bio, p.website
FROM users u
LEFT JOIN profiles p ON p.user_id = u.id
WHERE u.id = @id;

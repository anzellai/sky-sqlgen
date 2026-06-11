-- IN (@list) queries: the list param is typed `List <base>` and expanded into
-- N comma-joined placeholders at runtime via the shared `placeholders` helper.
CREATE TABLE widgets (
    id     INTEGER PRIMARY KEY,
    name   TEXT    NOT NULL,
    active BOOLEAN NOT NULL DEFAULT 1
);


-- Pure list param.
-- name: WidgetsByIds :many
SELECT id, name
FROM widgets
WHERE id IN (@ids)
ORDER BY id;


-- Mixed: a scalar param BEFORE the list (placeholder order preserved).
-- name: ActiveWidgetsByIds :many
SELECT id, name
FROM widgets
WHERE active = @active
  AND id IN (@ids)
ORDER BY id;


-- List then a scalar AFTER it (LIMIT), combined with :scalarmany.
-- name: WidgetNamesByIds :scalarmany
SELECT name
FROM widgets
WHERE id IN (@ids)
ORDER BY id
LIMIT @lim;

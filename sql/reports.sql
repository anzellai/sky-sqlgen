-- Schema (auto-detected; no name: annotation needed)
CREATE TABLE items (
    id    INTEGER PRIMARY KEY,
    name  TEXT    NOT NULL,
    qty   INTEGER NOT NULL
);

-- name: ItemStats :one
SELECT count(*) AS cnt,
       sum(qty) AS total_qty,
       avg(qty) AS avg_qty,
       min(qty) AS lo,
       max(qty) AS hi,
       coalesce(sum(qty), 0) AS safe_total
FROM items
WHERE qty > @min;

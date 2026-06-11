-- Derived-table sources: FROM (SELECT ...) sub. The subquery's output columns
-- (with their inferred types + nullability) synthesise a virtual table that the
-- outer projection resolves against.
CREATE TABLE sales (
    id     INTEGER PRIMARY KEY,
    region TEXT    NOT NULL,
    amount INTEGER NOT NULL
);


-- The subquery's `sum(amount) AS total` is a nullable aggregate, so the derived
-- `total` column comes out `Maybe Int`; `region` stays non-null.
-- name: RegionTotals :many
SELECT region, total
FROM (SELECT region, sum(amount) AS total FROM sales GROUP BY region) AS sub
ORDER BY region;


-- A param INSIDE the subquery (@min) is typed against the subquery's own scope.
-- name: BigRegions :many
SELECT region, total
FROM (SELECT region, sum(amount) AS total FROM sales WHERE amount > @min GROUP BY region) AS sub
ORDER BY region;


-- Derived table + a scalar outer projection.
-- name: RegionNames :scalarmany
SELECT region
FROM (SELECT region FROM sales) AS s
ORDER BY region;

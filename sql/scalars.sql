-- Scalar queries: single-column projections decoded without a Row alias.
CREATE TABLE products (
    id    INTEGER PRIMARY KEY,
    name  TEXT    NOT NULL,
    price INTEGER NOT NULL
);


-- Single non-null column -> Maybe String (the Maybe is row-presence).
-- name: ProductName :scalar
SELECT name
FROM products
WHERE id = @id;


-- Many non-null values -> List String.
-- name: AllNames :scalarmany
SELECT name
FROM products
ORDER BY id;


-- count(*) is non-null Int -> Maybe Int.
-- name: ProductCount :scalar
SELECT count(*) AS n
FROM products;


-- max(price) is a nullable aggregate -> element type is (Maybe Int), so the
-- scalar result is Maybe (Maybe Int): outer = row presence, inner = NULL agg.
-- name: MaxPrice :scalar
SELECT max(price) AS hi
FROM products;

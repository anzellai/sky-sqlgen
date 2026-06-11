-- Billing schema + queries: exercises NUMERIC/DECIMAL/MONEY currency mapping.
CREATE TABLE invoices (
    id INTEGER PRIMARY KEY,
    customer TEXT NOT NULL,
    price NUMERIC NOT NULL,
    discount NUMERIC,
    total MONEY NOT NULL,
    created_at TEXT NOT NULL
);


-- name: GetInvoice :one
SELECT id, customer, price, discount, total, created_at
FROM invoices
WHERE id = @id;


-- name: ListInvoices :many
SELECT id, price, discount, total
FROM invoices
ORDER BY id;


-- name: ListPrices :many
SELECT id, price, discount
FROM invoices
ORDER BY id;


-- name: ExpensiveInvoices :many
SELECT id, total
FROM invoices
WHERE price > @min_price;


-- name: CreateInvoice :exec
INSERT INTO invoices (customer, price, discount, total, created_at)
VALUES (@customer, @price, @discount, @total, @created_at);

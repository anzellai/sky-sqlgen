-- Accounts schema + queries: exercises [[sqlgen.override]] sky_type and @model.
-- `balance` is stored as TEXT in SQLite but the override types it Money;
-- `rate` defaults to Float (REAL) but the override types it Decimal.
CREATE TABLE accounts (
    id      INTEGER PRIMARY KEY,
    owner   TEXT    NOT NULL,
    balance TEXT    NOT NULL,
    rate    REAL
);


-- @model renames the generated Model for `accounts` from `Account` to `Ledger`
-- everywhere (Schema alias + decoder, the reuse below, and the import).
-- name: GetAccount :one
-- @model Ledger
SELECT id, owner, balance, rate
FROM accounts
WHERE id = @id;


-- name: ListOwners :many
SELECT id, owner
FROM accounts
ORDER BY id;

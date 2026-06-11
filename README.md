# sky-sqlgen

Type-safe SQL for [Sky](https://github.com/anzellai/sky), à la
[sqlc](https://sqlc.dev) / [squirrel](https://github.com/giacomocavalieri/squirrel).

Write plain `.sql` files with a one-line magic comment per statement; `sky-sqlgen`
generates fully-typed Sky modules — a `Model`/`Row` record + decoder + a
parameter-typed query function for every statement, and `type alias` Models from
your `CREATE TABLE` DDL. The generated code goes through `sky check` (which runs
`go build`), so a codegen bug can't produce ill-typed Sky: **if it generates, it
compiles.**

```sql
-- sql/users.sql
CREATE TABLE users (
    id     INTEGER PRIMARY KEY,
    name   TEXT    NOT NULL,
    email  TEXT    NOT NULL,
    bio    TEXT
);

-- name: GetUser :one
SELECT id, name, email, bio FROM users WHERE id = @id;

-- name: ListUsers :many
SELECT id, name FROM users ORDER BY name;

-- name: CreateUser :execrows
INSERT INTO users (name, email, bio) VALUES (@name, @email, @bio);
```

generates `src/Gen/Schema.sky` (the `User` Model + `userDecoder`) and
`src/Gen/Users.sky`:

```elm
getUser : Db -> GetUserParams -> Task Error (Maybe User)
listUsers : Db -> Task Error (List ListUsersRow)
createUser : Db -> CreateUserParams -> Task Error Int
```

— mixed-type params (`String`, `Maybe Int`, `Bool`, …) bound losslessly via the
`SqlValue` ADT; `bio` correctly typed `Maybe String`; `GetUser` reuses the `User`
Model (full projection) while `ListUsers` gets its own `ListUsersRow` (partial).

## Install

Download a prebuilt binary (linux / macOS, amd64 / arm64) for your machine:

```bash
curl -fsSL https://raw.githubusercontent.com/anzellai/sky-sqlgen/main/install.sh | sh
```

Installs `sky-sqlgen` to `/usr/local/bin` (override with `--dir ~/.local/bin`, or
pin a version with `--version v0.1.0`). Then run `sky-sqlgen --version`. Releases
are at [github.com/anzellai/sky-sqlgen/releases](https://github.com/anzellai/sky-sqlgen/releases).

> Building from source needs the [Sky](https://github.com/anzellai/sky) compiler:
> `sky build src/Main.sky` → `sky-out/app`.

## Quick start

```bash
sky-sqlgen                      # generate + sky fmt + sky check (reads sky.toml)
```

Add a `[sqlgen]` section to `sky.toml` (see [Configuration](#configuration)),
put `.sql` files where it points, run `./sky-out/app`, and `import Gen.<File>` /
`import Gen.Schema` from your app. Commit the generated `src/Gen/**` and gate it
in CI with `--check` (below).

## CLI

```
sky-sqlgen                 # generate into the configured out dir, fmt + verify
sky-sqlgen --check         # CI drift gate: regenerate to a temp dir, diff the
                           #   committed output, exit 1 if stale/missing
sky-sqlgen --dry-run       # print the paths that would be written, write nothing
sky-sqlgen --no-verify     # skip the post-emit `sky check` (faster inner loop)
sky-sqlgen --config PATH   # use an alternate config file (default: sky.toml)
sky-sqlgen --version
```

(From source, it's `./sky-out/app` instead of `sky-sqlgen`.)

CI recipe:
```bash
sky-sqlgen --check         # fails the build if generated code is stale
```

## Configuration

```toml
[sqlgen]
dialect     = "sqlite"          # "sqlite" | "postgres"  (placeholder + IN-list rules)
schema      = ["sql/schema.sql"] # DDL globs — build the catalog (CREATE TABLE)
queries     = ["sql/*.sql"]      # DML globs — generate a module per file
out         = "src/Gen"          # output directory
module      = "Gen"              # module prefix -> Gen.Schema, Gen.Users, ...
singularize = true               # table `users` -> Model `User`
verify      = true               # run `sky check` on the output after emit
decimal_as  = "decimal"          # NUMERIC/DECIMAL -> "decimal" (lossless, default)
                                 #                   | "float" (lossy opt-out) | "money"

# Per-column type override — wins over the default SQL-type -> Sky-type mapping.
[[sqlgen.override]]
column   = "accounts.balance"
sky_type = "Money"               # Int | Float | String | Bool | Bytes | Decimal | Money

[[sqlgen.override]]
column   = "accounts.rate"
sky_type = "Decimal"
```

A file may both declare (`CREATE TABLE`) and query a table; the catalog is built
from `schema` ∪ `queries` before any statement is typed, so queries can reference
tables declared in other files. Keep separate `sky.<name>.toml` configs when two
files declare a same-named table (see this repo's `sky.*.toml`).

**No config?** Loading is best-effort — a missing `sky.toml`, a missing `[sqlgen]`
section, or any absent key falls back to defaults: `dialect=sqlite`,
`schema=["sql/schema.sql"]`, `queries=["sql/*.sql"]`, `out="src/Gen"`,
`module="Gen"`, `singularize=true`, `verify=true`, `decimal_as="decimal"`. A
schema/query glob that matches nothing yields no files (not an error), and the
catalog is still built from any `CREATE TABLE` in the queried files. So for the
conventional layout — `.sql` files under `sql/` — you can run with no config at
all and get `src/Gen/`.

## Statement annotations

Annotations are **optional**. Point the tool at any `.sql` file and it just
works: every statement it understands gets a typed function, anything it can't
handle is skipped with a `file:line` warning (the run still succeeds), and
unannotated statements are **auto-named** from the catalog. A magic comment is
an *override* — it pins a stable name + cardinality:

```sql
-- name: GetUser :one
```

When a statement has no `-- name:`, the name + cardinality are derived from the
SQL: `getUserById` (SELECT by primary key → `:one`), `listUsersByActive`
(SELECT by a non-key column → `:many`), `createUser` (INSERT → `:execrows`),
`updateUserById` / `deleteUserById`, etc. Names that clash within a module get
an integer suffix (`getUserById`, `getUserById1`, …) — never an error. See
[`design/README.md`](design/README.md#auto-naming--skip-and-warn) for the full
rules. Auto-names are *content-derived* (editing the SQL can change the name);
add an explicit `-- name:` when you want a name that survives edits.

| Cardinality | Returns | Notes |
|---|---|---|
| `:one` | `Task Error (Maybe Row)` | first row or `Nothing` |
| `:many` | `Task Error (List Row)` | |
| `:exec` | `Task Error ()` | INSERT/UPDATE/DELETE, ignore count |
| `:execrows` | `Task Error Int` | affected-row count |
| `:scalar` | `Task Error (Maybe T)` | single-column projection, bare value (no Row) |
| `:scalarmany` | `Task Error (List T)` | single-column projection |

`CREATE TABLE` / `CREATE INDEX` need no annotation — they're auto-detected and
feed the catalog. An unannotated DML statement is auto-named from the catalog
(above); an explicit `-- name:` always wins.

### Parameters

Named `@ident` placeholders, rewritten to the dialect form (`?` for sqlite,
`$1,$2,…` for postgres) on emit; the Params record carries one field per distinct
param, typed from the column it's compared/assigned against:

```sql
-- name: FindByAge :many
SELECT id, name FROM users WHERE age >= @min_age ORDER BY name;
```

Directives (each on its own `--` line above the statement):

| Directive | Effect |
|---|---|
| `-- @param min_age Int` | force a param's Sky type (`Int`/`Float`/`String`/`Bool`/`Bytes`/`Maybe T`) |
| `-- @notnull col` | force a result column non-null |
| `-- @nullable col` | force a result column `Maybe` |
| `-- @model Name` | rename the generated Model for this statement's table |
| `-- @omit col, …` | mark INSERT columns as DEFAULT-omittable (see below) |

Per-column inline overrides also work: `SELECT coalesce(sum(x),0) AS "total!"`
forces non-null; `AS "note?"` forces `Maybe`. Per-param: `@id!` non-null, `@id?`
nullable.

## Type & nullability rules

**SQL → Sky base types** (case-insensitive, size/precision-tolerant):
`INTEGER/INT/SERIAL…→Int`, `REAL/FLOAT/DOUBLE→Float`, `NUMERIC/DECIMAL→Decimal`
(lossless; `decimal_as` to change), `MONEY→Money`, `TEXT/VARCHAR/UUID/JSON…→String`,
`BOOLEAN→Bool`, `BLOB/BYTEA→Bytes`. Unknown types are a hard error (add an override).

**Result-column nullability** (top rule wins): per-column `AS "c!"`/`AS "c?"`;
**outer-join demotion** (a column from the nullable side of a `LEFT`/`RIGHT`/`FULL`
JOIN becomes `Maybe`, even if the catalog says `NOT NULL`); aggregates
(`COUNT→Int` non-null, `SUM`/`MIN`/`MAX→Maybe`, `AVG→Maybe Float`,
`COALESCE(agg, lit)→` non-null); plain catalog columns (`NOT NULL`/`PRIMARY KEY →`
non-null, else nullable). Anything the analyzer can't classify is a clear error,
not a silent guess.

## Supported SQL

- **DDL**: `CREATE TABLE` (`PRIMARY KEY`/`NOT NULL`/`UNIQUE`/`DEFAULT`; other
  constraints tolerated).
- **SELECT**: plain/`*`/`t.*`/aggregate projections; `FROM` + `INNER`/`LEFT`/
  `RIGHT`/`FULL`/`CROSS` `JOIN … ON …` or `… USING (col)`; derived-table sources
  `FROM (SELECT …) sub`; `WHERE`/`ORDER BY`/`LIMIT`/`OFFSET`; `col IN (@list)`.
- **INSERT** (incl. `@omit` DEFAULT columns), **UPDATE**, **DELETE**; all with
  optional `RETURNING <projection>` (→ typed Row/scalar via `queryDecode`).

### `IN (@list)`

```sql
-- name: UsersByIds :many
SELECT id, name FROM users WHERE id IN (@ids);
```
`@ids : List Int`; the generated function expands the placeholders at runtime
(`IN (?, ?, …)`) from the list length and binds each element. Mixing list and
scalar params in one statement preserves placeholder order.

### DEFAULT-omittable INSERT (`@omit`)

```sql
-- name: CreateItem :execrows
-- @omit status, note
INSERT INTO items (name, status, note) VALUES (@name, @status, @note);
```
Listed columns become `SqlField`-typed params (`Db.SetField v` to bind a value,
`Db.SetField (Db.SqlNull …)` for explicit NULL, `Db.OmitField` to drop the column
so the DB `DEFAULT` applies). Other columns are unchanged. A `NOT NULL` column
without a `DEFAULT` can't be omitted (hard error). Emits a `Db.insertFields` call;
with a `RETURNING` clause it emits `Db.insertFieldsReturning` (so `@omit` composes
with `RETURNING` → typed Row/scalar, the returned row reflecting DB-applied
defaults).

## Worked examples

The `sql/` directory + matching `sky.*.toml` configs are runnable demos, each
generating into its own `src/Gen*/`:

| File | Demonstrates |
|---|---|
| `users.sql` | the basics — Model reuse vs partial Row, mixed params |
| `joins.sql` | `LEFT`/`INNER` JOIN + outer-join nullability demotion |
| `usingjoins.sql` | `JOIN … USING (col)` |
| `derived.sql` | `FROM (SELECT …) sub` derived-table sources |
| `billing.sql` | lossless `Decimal`/`Money` columns |
| `reports.sql` | `COUNT`/`SUM`/`AVG`/`MIN`/`MAX`/`COALESCE` nullability |
| `accounts.sql` | `[[sqlgen.override]]` + `@model` rename |
| `scalars.sql` | `:scalar` / `:scalarmany` |
| `returning.sql` | `RETURNING` on INSERT/UPDATE/DELETE |
| `inlist.sql` | `IN (@list)` runtime expansion |
| `omit.sql` | `@omit` DEFAULT-omittable INSERT |
| `auto.sql` | **zero annotations** — auto-naming, suffix-on-clash, skip-and-warn |

Run one: `./sky-out/app --config sky.joins.toml`.

## Generated output

Per `.sql` file → one `Gen.<File>` module (Params/Row aliases, decoders, SQL
constants, query functions). All Models + their decoders are hoisted to a shared
`Gen.Schema` so a table referenced across files is defined once. Every file carries
a `-- Code generated by sky-sqlgen; DO NOT EDIT.` header and is `sky fmt`-clean.
Commit it and gate with `--check`.

## Design & internals

See `design/DESIGN.md` for the architecture (squirrel-vs-sqlc analysis, the
catalog model, the naming scheme, the verified emit contract) and
`design/IMPL-PUSHBACK.md` for the implementation log and the per-feature notes.

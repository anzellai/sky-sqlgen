# sky-sqlgen — design

How the generator is put together, and the decisions behind it. For usage see the
top-level [README](../README.md).

## Strategy: static catalog (sqlc model), not live introspection (squirrel)

The two reference points sit at opposite ends of "where do the types come from?":

- **squirrel** (Gleam) asks a live PostgreSQL to `PREPARE` each query and reports
  the inferred types. Accurate, zero schema modelling — but needs a running,
  migrated Postgres at codegen time, is Postgres-only, can't type nullable
  *parameters*, and mandates one query per file.
- **sqlc** (Go) statically parses the SQL, builds a **catalog** from your
  `CREATE TABLE` DDL, and infers param/result types from it. No live DB,
  multi-dialect, many queries per file.

sky-sqlgen follows **sqlc**, because:

1. **"If it compiles, it works"** — emitted Sky is fed back through `sky check`
   (which runs `go build`), giving a second, independent verification of the
   codegen. No "works against the DB I happened to have running" ambiguity.
2. **No live DB at codegen time** — works in CI, on fresh checkouts, and for the
   SQLite story, none of which squirrel's PREPARE supports.
3. **Multi-dialect by construction** — the catalog is built from DDL we parse, so
   dialect differences (placeholders, type spellings) are a lookup table.
4. **The requested features fall out of the catalog** — many statements per file,
   `CREATE TABLE → Model`, partial-select Rows, overrides — all native to a
   static catalog and at odds with live-PREPARE.

The price: a SQL parser over a bounded subset, and heuristic (not oracle)
nullability. We pay it with explicit escape hatches and a loud-failure policy —
anything off-subset is a clear `file:line` error, never silent wrong output.

## Pipeline

```
sql/*.sql ─▶ Discover ─▶ Lex/Parse ─▶ Catalog ─▶ Type-infer ─▶ Name ─▶ Emit ─▶ Verify
            (globs)     (subset AST   (CREATE     (params,      (fn/      (Sky     (sky
                         + magic       TABLE →     results,      Model/    source)  check)
                         comments)     types)      nullability)  Row)
```

Two-phase ordering is mandatory: **all** schema statements across **all** files
build the catalog before **any** query is typed, so a query can reference a table
declared in another file.

## Modules

| Module | Responsibility |
|---|---|
| `Main` | CLI, arg parse, orchestrate, `--check` drift gate, exit codes |
| `SqlGen.Config` | read `[sqlgen]` from `sky.toml` (incl. `[[sqlgen.override]]`) |
| `SqlGen.Lexer` | SQL `String` → tokens; magic-comment + `@directive` parsing |
| `SqlGen.Parser` | recursive-descent tokens → `ParsedStmt` (DDL + DML subset) |
| `SqlGen.Catalog` | DDL → catalog; SQL-type → Sky-type mapping |
| `SqlGen.Infer` | per-statement param + result-column + nullability inference |
| `SqlGen.Naming` | base → fn / Model / Row / Params; snake→camel; collisions |
| `SqlGen.Emit` | resolved statements → Sky source (`Gen.Schema` + per-file) |
| `SqlGen.Pipeline` | two-phase orchestration + cross-statement collision checks |
| `SqlGen.Types` | shared types (tokens, AST, catalog, resolved statements, config) |

## Catalog & type mapping

`CREATE TABLE` columns map to five base Sky types plus the money types
(case-insensitive, size/precision-tolerant): `INTEGER…→Int`, `REAL/FLOAT/DOUBLE→
Float`, `NUMERIC/DECIMAL→Decimal` (lossless; `decimal_as` knob), `MONEY→Money`,
`TEXT/VARCHAR/UUID/JSON…→String`, `BOOLEAN→Bool`, `BLOB/BYTEA→Bytes`. Unknown
types are a hard error (add a `[[sqlgen.override]]`). `NOT NULL`/`PRIMARY KEY` ⇒
non-null, else nullable.

## Nullability (the hard part)

Result-column nullability, top rule wins: per-column `AS "c!"`/`AS "c?"`;
**outer-join demotion** (a column from the nullable side of a `LEFT`/`RIGHT`/
`FULL` JOIN becomes `Maybe`, even if the catalog says `NOT NULL`); aggregates
(`COUNT→Int`, `SUM`/`MIN`/`MAX→Maybe`, `AVG→Maybe Float`, `COALESCE(agg,lit)→`
non-null); plain catalog columns. Anything unclassifiable is a clear error, never
a silent guess.

## Naming

`-- name: GetUser` is the PascalCase base; everything derives deterministically:
function `getUser`, `GetUserParams`, partial-projection `GetUserRow` (+
`getUserRowDecoder`). Tables singularise to Models (`users → User`), columns
snake→camel. A partial projection **must** get a named `<Base>Row` — Sky forbids
anonymous records in signatures, so the named-Row discipline is mandatory and
compiler-checked, not an optimisation.

## Emit contract

Generated code targets the typed `Std.Db` surface:

- **Params**: homogeneous `List SqlValue` (`Db.SqlInt`/`SqlString`/`SqlFloat`/
  `SqlBool`/`SqlBytes`/`SqlDecimal`/`SqlMoney`), nullable via `Db.fromMaybe*`.
- **Decoders**: `DbDecode.succeed Ctor |> DbDecode.andMap (DbDecode.int "c") | …`,
  nullable columns `DbDecode.nullable (DbDecode.int "c")`, Decimal via a generated
  `decimalCol` helper, Money via `DbDecode.money`.
- **Cardinality**: `:one` = `queryDecode |> Task.map List.head`; `:many` = bare
  `queryDecode`; `:scalar`/`:scalarmany` decode a single column to a bare value;
  `:exec`/`:execrows` = `Db.exec`.
- **`IN (@list)`**: runtime placeholder expansion (`IN (?, ?, …)` from list length).
- **`@omit`**: `Db.insertFields` (or `Db.insertFieldsReturning` with `RETURNING`)
  over `SqlField` (`SetField v` / `OmitField`) — DEFAULT-omittable columns.

All Models + decoders are hoisted to a shared `Gen.Schema`; each `.sql` file emits
one `Gen.<File>` module. Output carries a `DO NOT EDIT` header, is `sky fmt`-clean,
committed to the repo, and CI-gated with `--check`.

## Supported SQL subset

`CREATE TABLE` (PK/NOT NULL/UNIQUE/DEFAULT); `SELECT` (plain/`*`/aggregate
projections, `FROM` + `INNER`/`LEFT`/`RIGHT`/`FULL`/`CROSS` `JOIN … ON`/`USING`,
derived-table `FROM (SELECT …) sub`, `WHERE`/`ORDER BY`/`LIMIT`, `IN (@list)`);
`INSERT`/`UPDATE`/`DELETE` with optional `RETURNING`. Off-subset constructs are
skipped with a `file:line` warning (see below), not a fatal error.

## Auto-naming & skip-and-warn

Magic comments are **optional**. The goal: point the tool at any `.sql` file and
it generates typed Sky for everything it understands and warns (without
aborting) for the rest — zero annotations required. An explicit `-- name: X
:card` always wins; the rules below only fire when a statement has no `-- name:`.

### Auto-naming (no `-- name:`)

A statement's name is `verb + Entity + By<cols>`, with an inferred cardinality —
all derived from the catalog (`SqlGen.Auto`):

- **Verb + cardinality**
  - `SELECT` → `get` + `:one` when a WHERE equality (`col = @p`) binds a
    **PRIMARY KEY** or **UNIQUE** column of the queried table (so it selects at
    most one row), *or* the projection is aggregate-only; otherwise `list` +
    `:many`.
  - `INSERT` → `create`; `:execrows` (no `RETURNING`) or `:one` (with
    `RETURNING` — a single `VALUES` row).
  - `UPDATE` → `update`; `:execrows` or `:many` (with `RETURNING`).
  - `DELETE` → `delete`; `:execrows` or `:many` (with `RETURNING`).
- **Entity** — the target table (the `FROM` / `INTO` / `UPDATE` / `DELETE FROM`
  table; the `FROM` table for a JOIN). `list` keeps the table name as-is,
  PascalCased (`listUsers`); the singular verbs use the singularised form
  (`getUser`, `createUser`), reusing `SqlGen.Naming.singularizeTable`.
- **By<cols>** — the WHERE equality columns bound to params, PascalCased and
  joined with `And`, prefixed `By` (`ById`, `ByEmail`, `ByOrgIdAndStatus`).
  None → omitted.

The PK/UNIQUE signal needs the catalog to know which columns are unique:
`CatColumn` carries a `unique` flag, populated from per-column `UNIQUE` and
table-level `UNIQUE(col)` constraints (the parser already captured the former).

Naming never fails. An undeterminable entity falls back to `<Verb>Query`. The
derived base name then feeds the existing fn / `Params` / `Row` / decoder
derivation unchanged, so an auto-named statement is indistinguishable downstream
from an annotated one.

### Suffix-on-clash

Names are assigned per module in source order. All explicit `-- name:` names are
reserved first (a duplicate of another *explicit* name is still a hard error —
the author owns that namespace). Each auto-name is then made unique against the
already-assigned set: if the derived name is taken, the smallest integer suffix
that makes it unique is appended (`getUserById`, `getUserById1`, `getUserById2`,
…). The suffix applies to the whole family — fn + `Params` + `Row` + decoder +
SQL const — so they stay aligned. Auto-names never error; they suffix.

### Skip-and-warn

A per-statement **parse or type/infer** failure no longer aborts the run.
`SqlGen.Pipeline` excludes that statement, emits a `[skip] file:line: <reason>`
warning to stderr, and continues with the rest; at the end it prints
`generated N function(s), skipped M`. A `CREATE TABLE` that fails to parse is
likewise skipped (its dependent queries then fail to type and skip too,
naturally). The process exit code stays `0` when generation succeeded — skips
are warnings, not failures; only a hard config/IO error (unknown SQL type,
duplicate table, duplicate *explicit* name, bad override) is fatal. `--check`
keeps its semantics: it diffs whatever was generated.

This is what makes "point at any `.sql`" hold even when the file contains a
`WITH`/CTE, a window function, or another off-subset construct — those
statements skip with a warning instead of breaking the whole run.

### Caveat — content-derived names

Auto-names are derived from the SQL, so editing a statement (changing its WHERE
columns, projection, or target table) can change the generated function name and
break call sites. When you want a name that survives edits, add an explicit
`-- name:` — it's an override, not a requirement.

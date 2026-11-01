# skink-postgres

PostgreSQL driver for Skink: a pure-Skink implementation of the v3
wire protocol — no libpq, no native dependencies — built on
[`skink-dbx`](../skink-dbx). Covers startup, TLS upgrade, cleartext /
MD5 / SCRAM-SHA-256 authentication, simple + extended query protocols,
parameter binding, typed result decoding, transactions, and a
`dbx.Driver` adapter.

## Installation

```sh
scales add mod/markoxley/skink-postgres
scales install          # also fetches the skink-dbx dependency
```

```skink
import "mod/markoxley/skink-postgres"
```

## Connecting

```skink
info, _ := dbx_dsn.ParseDSN("postgres://user:pass@localhost:5432/mydb")
c, err := postgres.Connect(info)
// or
c, err := postgres.Dial("postgres://user:pass@host/db?sslmode=require")
```

DSN form:

```
postgres://[user[:password]@]host[:port][/database]
    ?sslmode=disable|prefer|require
    &connect_timeout=<seconds>
    &application_name=<name>
```

`postgresql://` is accepted as an alias. `sslmode=prefer`/`require`
send the SSLRequest negotiation; `require` fails when the server lacks
TLS. SCRAM-SHA-256, MD5, and cleartext password auth are all supported
— the server picks.

## Queries

```skink
res, err := postgres.Query(&c,
    "SELECT id, name FROM users WHERE id = $1",
    []dbx_value.Value{dbx_value.Int(int64(7))})
for i := 0; i < len(res.Data); i = i + 1 {
    // res.Data[i][j] is a dbx_value.Value, res.Columns[i] its name
}

n, err := postgres.Exec(&c, "DELETE FROM t WHERE done = $1",
    []dbx_value.Value{dbx_value.Bool(true)})
```

`postgres.RewritePlaceholders(sql)` converts `?` markers to `$1..$N`
for callers using the dbx convention — quoting, dollar-quoting, and
comments are respected; existing `$N` markers are preserved and new
numbering continues above them.

## Types

Results are requested in text format and decoded by type OID:

| Postgres type | dbx_value kind |
|---------------|----------------|
| bool | `KIND_BOOL` |
| int2/int4/int8/oid | `KIND_INT` |
| float4/float8 | `KIND_FLOAT` |
| date/time/timestamp(tz) | `KIND_TIME` (Unix micros) |
| bytea | `KIND_BLOB` (raw bytes) |
| numeric, uuid, json(b), text, varchar, others | `KIND_TEXT` |

`numeric` stays text to preserve arbitrary precision — cast to
`::float8`/`::int8` in SQL when a number is wanted.

## Transactions

Transaction helpers live in the `pg_conn` submodule:

```skink
import "mod/markoxley/skink-postgres/pg_conn"

pg_conn.Begin(&c)
// ... c used normally
pg_conn.CommitTx(&c)   // or pg_conn.RollbackTx
```

`c.TxStatus` tracks the `ReadyForQuery` status byte (`'I'` idle,
`'T'` in-tx, `'E'` failed-tx) after every exchange.

## Generic dbx access

```skink
import "mod/markoxley/skink-dbx"
import "mod/markoxley/skink-dbx/dbx_value"

postgres.Register() // installs the "postgres" scheme driver
conn, err := dbx.Open("postgres://user:pass@host/db")
rows, _ := conn.Query("SELECT * FROM t WHERE id = ?", []dbx_value.Value{...})
tx, _  := conn.Begin(); tx.Exec(...); tx.Commit()
```

`Query`/`Exec` rewrite `?` placeholders automatically. `Ping` runs
`SELECT 1`.

## Layout

| file | contents |
|------|----------|
| `pg_msg`   | wire framing — OutBuf encoder, Cursor decoder, typed message I/O |
| `pg_type`  | OID ↔ `dbx_value` type bridge, timestamp/bytea codecs, param encoder |
| `pg_conn`  | `PgConn`, startup/auth/SSL negotiation, simple + extended queries |
| `pg_dbx`   | `dbx.Driver` adapter (scheme `postgres`) |
| `testkit`  | scripted in-process v3 backend used by the tests |

## Testing

```sh
./run_tests.sh    # unit + fake-backend integration suites
./test_live.sh    # live test vs a podman postgres:16 container
```

`test_live.sh` starts a throwaway container on 127.0.0.1:15432
(`POSTGRES_IMAGE`, `PG_PORT` override), runs `live_test.skink`, and
tears down. Use `SKINK_PG_DSN=postgres://... ./test_live.sh` to run
against an existing server — TLS with `?sslmode=require` on a TLS-enabled
server is exercised that way too.

## Notes & limits

- `PgConn` is not safe for concurrent use — use one connection per
  thread or a `dbx_pool` pool.
- Results are decoded in **text** format only (Bind result format 0).
- Channel binding (`SCRAM-SHA-256-PLUS`) is not used; `sslmode=verify-*`
  is not implemented (`require`/`prefer`/`disable` only).
- Skink strings are NUL-terminated: bound parameters cannot contain
  embedded NULs except via `KIND_BLOB` (bytea `\x` hex encoding).

## License

Apache-2.0

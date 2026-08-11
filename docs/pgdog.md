# PgDog lookup-routing demo

This setup uses PgDog `v0.1.52`, which includes
[PR #1279](https://github.com/pgdogdev/pgdog/pull/1279) and commit
`f2ae21ce7239be7b7f4208b1750bae1b29f83b62`.

It starts four database-related services:

- `postgres`: an unsharded control database used by Oban
- `shard_0`: PostgreSQL 18, exposed directly on port `5433`
- `shard_1`: PostgreSQL 18, exposed directly on port `5434`
- `pgdog`: the application endpoint on port `6432`, with metrics on `9090`

The Phoenix Repo uses PgDog by default in development. Oban uses the control database directly
because queue state must not be broadcast or independently duplicated across shards.

The dashboard's global totals issue one direct count per shard and sum the results in Elixir. This
also provides a small example of `pgdog_shard` directives for queries that intentionally span the
whole fleet rather than routing from an organization key.

## Start the cluster

```bash
docker compose up -d --wait
```

Apply the application migrations directly to each physical shard. Do not run migrations through
PgDog while learning the routing behavior.

```bash
DATABASE_PORT=5433 mix ecto.migrate -r ShardHound.Repo
DATABASE_PORT=5434 mix ecto.migrate -r ShardHound.Repo
mix ecto.migrate -r ShardHound.ObanRepo
```

Start Phoenix. Its domain Repo connects to PgDog on port `6432`; its Oban Repo connects to the
control database on port `5432`.

```bash
mix phx.server
```

## How placement works

`organizations` is omnisharded, so PgDog broadcasts organization writes to both shards. Each row
contains a stable, zero-based `shard_id`.

All tenant tables are matched by their `organization_id` column. On a cache miss PgDog executes:

```sql
SELECT shard_id FROM organizations WHERE id = $1
```

With `lookup_result = "shard"`, the result is used directly as the shard number. It is not hashed.
The organization row must be committed before inserting tenant rows.

Organization generation jobs then run `SET LOCAL pgdog.sharding_key = '<organization id>'` at the
start of their data transaction. PgDog resolves the value with the same lookup query and pins the
bulk inserts to that shard. This avoids treating a multi-row prepared insert as cross-shard traffic.

## Exercise fixed placement

Open a client through PgDog using the PostgreSQL client already available in the control container:

```bash
docker compose exec postgres \
  psql -h pgdog -p 6432 -U postgres -d shard_hound_dev
```

Create a mapping assigned to shard 1. The organization insert is broadcast to both shards.

```sql
INSERT INTO organizations
  (id, name, slug, shard_id, inserted_at, updated_at)
VALUES
  (900001, 'Lookup Demo', 'lookup-demo', 1, now(), now());
```

Insert a tenant row in a separate statement. PgDog looks up organization `900001` and sends this
row only to shard 1.

```sql
INSERT INTO devices
  (organization_id, serial_number, hostname, platform, architecture, os_version,
   metadata, inserted_at, updated_at)
VALUES
  (900001, 'LOOKUP-001', 'lookup-001', 'macos', 'arm64', '15.6', '{}', now(), now());
```

Leave the PgDog client with `\q`, then inspect each physical shard:

```bash
docker compose exec shard_0 \
  psql -U postgres -d shard_hound_dev -c \
  "SELECT id, shard_id FROM organizations WHERE id = 900001; SELECT serial_number FROM devices WHERE organization_id = 900001;"

docker compose exec shard_1 \
  psql -U postgres -d shard_hound_dev -c \
  "SELECT id, shard_id FROM organizations WHERE id = 900001; SELECT serial_number FROM devices WHERE organization_id = 900001;"
```

The organization exists on both shards, while the device exists only on shard 1.

Try an unmapped organization ID to see the fail-closed behavior:

```sql
INSERT INTO devices
  (organization_id, serial_number, hostname, platform, architecture, os_version,
   metadata, inserted_at, updated_at)
VALUES
  (999999, 'MISSING-001', 'missing-001', 'macos', 'arm64', '15.6', '{}', now(), now());
```

PgDog rejects it rather than hashing it or choosing an arbitrary shard.

## Observe lookups

Lookup cache and query metrics are exposed by PgDog:

```bash
curl -s http://localhost:9090/metrics | rg sharding_lookup
```

Useful logs are available with:

```bash
docker compose logs -f pgdog
```

## Reset the local demo

This deletes only the new Docker-backed local databases. It does not run PgDog resharding.

```bash
docker compose down -v
```

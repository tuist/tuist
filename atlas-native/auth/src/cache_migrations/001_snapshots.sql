CREATE TABLE cache_namespaces (
    id TEXT PRIMARY KEY NOT NULL,
    generation INTEGER NOT NULL DEFAULT 0,
    retired INTEGER NOT NULL DEFAULT 0 CHECK (retired IN (0, 1))
);

CREATE TABLE read_snapshots (
    namespace TEXT NOT NULL REFERENCES cache_namespaces(id),
    query_key TEXT NOT NULL,
    payload TEXT NOT NULL,
    fetched_at INTEGER NOT NULL,
    PRIMARY KEY (namespace, query_key)
);

CREATE INDEX read_snapshots_fetched_at ON read_snapshots(fetched_at);

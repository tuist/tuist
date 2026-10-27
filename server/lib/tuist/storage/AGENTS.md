# Artifact Retention

- Enforce Tuist Cloud and opt-in self-hosted artifact-retention windows without deleting analytics metadata.
- Expire run artifacts (`<account>/<project>/runs/<id>/`) by object age with a bucket sweep: their ID can be a command event, test run or legacy integer, so no single table lists them all.
- Expire a shard plan by deleting its whole `shards/<plan_id>/` prefix, including its bundle and per-module archives.

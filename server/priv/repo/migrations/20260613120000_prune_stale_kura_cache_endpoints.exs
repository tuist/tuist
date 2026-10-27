defmodule Tuist.Repo.Migrations.PruneStaleKuraCacheEndpoints do
  use Ecto.Migration
  # credo:disable-for-this-file ExcellentMigrations.CredoCheck.MigrationsSafety

  # One-shot cleanup for the Kura ingress-hostname collision fix
  # (environment-scoped public hosts). Before the fix, staging and canary
  # minted the *same* `*.kura.tuist.dev` hostnames as production — the
  # managed `eu-central` region is exposed in every environment and shares
  # a `cluster_id`, so `{handle}-eu-central-1.kura.tuist.dev` was identical
  # across environments and the Cloudflare record (via external-dns) ended
  # up owned by whichever cluster registered it first (production). The
  # fix makes non-production hosts carry an env suffix (`-staging` /
  # `-canary`), and the reconciler re-applies the KuraInstance and writes
  # the new suffixed endpoint on its next converge.
  #
  # `Tuist.Kura.ensure_cache_endpoint/2` upserts with the URL as part of
  # the conflict target and never deletes the superseded row, so the stale
  # (production-pointing) endpoint lingers alongside the new one and the
  # CLI can still resolve it. On staging/canary every legitimate Kura
  # public endpoint now carries the env suffix, so any `:kura` endpoint
  # whose host lacks it is stale.
  #
  # Gated to staging/canary; a no-op everywhere else. Production's
  # unsuffixed hosts are correct and must never be touched here.

  # account_cache_endpoints.technology is an Ecto.Enum stored as an integer
  # (`default: 0`, `kura: 1`).
  @kura_technology 1

  def up do
    case Tuist.Environment.env() do
      :stag -> prune_unsuffixed_kura_endpoints("-staging")
      :can -> prune_unsuffixed_kura_endpoints("-canary")
      _ -> :ok
    end
  end

  # The pruned rows are derived state: the reconciler rewrites the correct
  # env-suffixed endpoint from the region template on its next converge, so
  # there is nothing to restore (and the old, production-pointing host must
  # not be reintroduced).
  def down, do: :ok

  defp prune_unsuffixed_kura_endpoints(env_suffix) do
    # excellent_migrations:safety-assured-for-next-line raw_sql_executed
    execute("""
    DELETE FROM account_cache_endpoints
     WHERE technology = #{@kura_technology}
       AND url LIKE '%.kura.tuist.dev'
       AND url NOT LIKE '%#{env_suffix}.kura.tuist.dev'
    """)
  end
end

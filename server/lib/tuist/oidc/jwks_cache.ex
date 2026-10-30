defmodule Tuist.OIDC.JWKSCache do
  @moduledoc "Disposable, size-limited storage for normalized workload signing keys."

  import Cachex.Spec, only: [expiration: 1, hook: 1]

  alias Tuist.KeyValueStore

  @cache :oidc_jwks
  @ttl to_timeout(minute: 15)

  def child_spec(opts) do
    cache = Keyword.get(opts, :cache, @cache)
    maximum_entries = Keyword.get(opts, :maximum_entries, 1_000)

    Supervisor.child_spec(
      {Cachex,
       [
         cache,
         [
           expiration: expiration(default: @ttl),
           hooks: [hook(module: Cachex.Limit.Scheduled, args: {maximum_entries, [], [frequency: 1_000]})]
         ]
       ]},
      id: __MODULE__
    )
  end

  def get_or_update(url, fetch, opts \\ []) do
    KeyValueStore.get_or_update(
      ["oidc", "workload-jwks", url],
      [cache: Keyword.get(opts, :cache, @cache), ttl: @ttl],
      fetch
    )
  end
end

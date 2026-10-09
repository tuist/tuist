defmodule Tuist.Authentication.TokenVerificationCache do
  @moduledoc """
  Caches only the immutable proof that a secret matches a stored bcrypt hash.

  Callers must load the token from authoritative storage and check revocation,
  expiration, users and scopes on every request, before using this proof. Neither
  subjects nor authorization decisions belong here. This dedicated, node-local
  cache survives display-cache invalidations and distribution membership changes.
  """

  import Cachex.Spec, only: [expiration: 1, hook: 1]

  @cache :token_verification
  @ttl to_timeout(minute: 1)
  @max_entries 10_000

  def child_spec(opts) do
    cache = Keyword.get(opts, :cache, @cache)
    ttl = Keyword.get(opts, :ttl, @ttl)

    Supervisor.child_spec(
      {Cachex,
       [
         cache,
         [
           expiration: expiration(default: ttl),
           hooks: [hook(module: Cachex.Limit.Scheduled, args: {@max_entries, [], []})]
         ]
       ]},
      id: __MODULE__
    )
  end

  def verify_pass(password, stored_hash, opts \\ []) do
    cache = Keyword.get(opts, :cache, @cache)
    key = :crypto.hash(:sha256, :erlang.term_to_binary({password, stored_hash}))

    # Single-flight per key, not a cache-wide transaction: one cold credential
    # must not serialize unrelated credentials or rerun bcrypt for every waiter.
    case Cachex.fetch(cache, key, fn ->
           started_at = System.monotonic_time()
           verified = Bcrypt.verify_pass(password, stored_hash)

           :telemetry.execute(
             [:tuist, :authentication, :bcrypt_verification],
             %{count: 1, duration: System.monotonic_time() - started_at},
             %{outcome: if(verified, do: :valid, else: :invalid)}
           )

           if verified, do: {:commit, true}, else: {:ignore, false}
         end) do
      true -> true
      {:commit, true} -> true
      _ -> false
    end
  rescue
    ArgumentError -> false
  end
end

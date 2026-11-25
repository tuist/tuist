defmodule Atlas.Release do
  alias Atlas.Authorization.Bootstrap
  alias Atlas.Demo
  alias Atlas.Demo.Seeds
  alias Atlas.Repo
  alias Atlas.Vault
  alias Atlas.Vault.Reencryption

  @app :atlas

  def bootstrap_admin do
    load_app()

    email =
      System.get_env("ATLAS_BOOTSTRAP_ADMIN_EMAIL") ||
        raise "ATLAS_BOOTSTRAP_ADMIN_EMAIL must identify a user who has already signed in"

    {:ok, result, _apps} = Ecto.Migrator.with_repo(Repo, fn _repo -> Bootstrap.run(email) end)

    case result do
      {:ok, user} ->
        IO.puts("Administrator access granted to #{user.email}.")

      {:error, :already_initialized} ->
        raise "Atlas already has an administrator or has previously been initialized"

      {:error, :user_not_found} ->
        raise "The selected user must sign in to Atlas before administrator access can be granted"

      {:error, :ambiguous_email} ->
        raise "Multiple users match the selected email; resolve the duplicate identities before initializing Atlas"

      {:error, _reason} ->
        raise "Atlas administrator initialization failed; no access was granted"
    end
  end

  def seed_demo do
    load_app()
    if !Demo.enabled?(), do: raise("Demo seeding requires ATLAS_DEMO_MODE=true")
    {:ok, {:ok, :seeded}, _apps} = Ecto.Migrator.with_repo(Repo, fn _repo -> Seeds.run!() end)
    IO.puts("Fictional Atlas demo data seeded.")
  end

  @doc """
  Re-encrypts every stored `Atlas.Encrypted.Binary` value under `key_id`, which
  must already be the current encryption key (`ENCRYPTION_CURRENT_KEY`) on
  every node:

      bin/atlas eval 'Atlas.Release.reencrypt_vault("<key id>")'

  It works in bounded batches and skips values already under the key, so rerun
  it after an interruption. Raises, so the command exits nonzero, when a value
  could not be decrypted with any configured key; drop a retired key only after
  a run passes. Options: `batch_size` (default 500).
  """
  def reencrypt_vault(key_id, opts \\ []) when is_binary(key_id) do
    load_app()

    {:ok, counts, _apps} =
      Ecto.Migrator.with_repo(Repo, fn _repo -> with_vault(fn -> Reencryption.run(key_id, opts) end) end)

    for {field, %{reencrypted: reencrypted, changed: changed}} <- Enum.sort(counts),
        reencrypted + changed > 0 do
      IO.puts("#{field}: #{reencrypted} re-encrypted, #{changed} changed concurrently (rerun to cover them)")
    end

    failed = for {field, %{failed: failed}} <- Enum.sort(counts), failed != 0, do: "#{field} (#{failed})"

    if failed != [] do
      raise "Some values could not be re-encrypted: #{Enum.join(failed, ", ")}. Keep the retired keys."
    end

    counts
  end

  def migrate do
    load_app()

    for repo <- repos() do
      {:ok, _, _} = Ecto.Migrator.with_repo(repo, &Ecto.Migrator.run(&1, :up, all: true))
    end
  end

  def rollback(repo, version) do
    load_app()
    {:ok, _, _} = Ecto.Migrator.with_repo(repo, &Ecto.Migrator.run(&1, :down, to: version))
  end

  defp repos do
    Application.fetch_env!(@app, :ecto_repos)
  end

  defp with_vault(fun) do
    if Process.whereis(Vault) do
      fun.()
    else
      {:ok, pid} = Vault.start_link()

      try do
        fun.()
      after
        GenServer.stop(pid)
      end
    end
  end

  defp load_app do
    Application.load(@app)
  end
end

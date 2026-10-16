defmodule Atlas.Release do
  alias Atlas.Authorization.Bootstrap
  alias Atlas.Demo
  alias Atlas.Demo.Seeds
  alias Atlas.Repo

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

  defp load_app do
    Application.load(@app)
  end
end

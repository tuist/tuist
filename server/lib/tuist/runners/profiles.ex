defmodule Tuist.Runners.Profiles do
  @moduledoc """
  CRUD + dispatch lookup for account-scoped Runner Profiles.

  A profile is a per-account alias for one entry in the shape
  catalog (see `Tuist.Runners.Catalog`). Customers reference it in
  `runs-on:` as `<Profile.prefix()><name>` (env-specific prefix); the
  dispatch path resolves `(account, requested-label)` through
  `match_for_dispatch/2` to the profile, then through the catalog to
  the K8s shape pool.

  All operations are pure Postgres — there is no K8s round-trip
  on profile mutation. The shape pools the profiles point at are
  pre-rendered by Helm (`runnersFleetLinux.shapes`), so a profile
  create / update never needs to materialise a new pool.

  ## Name immutability

  Profile name is the identity in `runs-on:`. Renaming would break
  every workflow that references the old name silently (the next
  dispatch would return `:no_matching_profile`), so `update/2`
  refuses to change `name`. Customers wanting a new name create a
  new profile, update workflows, then delete the old one.
  """
  import Ecto.Query

  alias Tuist.Repo
  alias Tuist.Runners.Catalog
  alias Tuist.Runners.Profile

  @max_per_account 10

  @doc """
  Cap on profiles per account. Surfaced so the LiveView can disable
  the "New profile" CTA when reached.
  """
  def max_per_account, do: @max_per_account

  @doc """
  Profiles for the given account, ordered by name for stable UI
  rendering.
  """
  def list_for_account(%{id: account_id}) do
    Profile
    |> where([p], p.account_id == ^account_id)
    |> order_by([p], asc: p.name)
    |> Repo.all()
  end

  @doc """
  Fetch one profile by `(account, name)`. Returns `nil` when not
  found.
  """
  def get_by_name(%{id: account_id}, name) when is_binary(name) do
    Repo.get_by(Profile, account_id: account_id, name: name)
  end

  @doc """
  Create a profile under `account`. Validates `vcpus`/`memory_gb`
  against the live catalog and the per-account cap.
  """
  def create(%{id: account_id}, attrs) do
    catalog = Catalog.list()

    if count_for_account(account_id) >= @max_per_account do
      {:error, :max_profiles_reached}
    else
      attrs = Map.put(stringify_keys(attrs), "account_id", account_id)

      %Profile{}
      |> Profile.changeset(attrs, catalog)
      |> Repo.insert()
    end
  end

  @doc """
  Update a profile's resources. `name` cannot change post-create
  (see module docs). Passing `name` is silently ignored.
  """
  def update(%Profile{} = profile, attrs) do
    catalog = Catalog.list()

    attrs =
      attrs
      |> stringify_keys()
      |> Map.drop(["name", "account_id"])

    profile
    |> Profile.changeset(attrs, catalog)
    |> Repo.update()
  end

  @doc """
  Delete a profile. Workflows still referencing it will hit
  `:no_matching_profile` on their next dispatch; in-flight Pods
  already claimed against the corresponding shape pool finish
  normally (the shape pool isn't going anywhere).
  """
  def delete(%Profile{} = profile), do: Repo.delete(profile)

  @doc """
  Resolve `(account, requested_labels)` → profile, mirroring the
  case-insensitive label matching the dispatch layer used pre-
  profiles. Returns `{:ok, profile}` or `{:error,
  :no_matching_profile}`.
  """
  def match_for_dispatch(%{id: account_id}, requested_labels) when is_list(requested_labels) do
    needles =
      requested_labels
      |> Enum.filter(&is_binary/1)
      |> MapSet.new(&String.downcase/1)

    Profile
    |> where([p], p.account_id == ^account_id)
    |> Repo.all()
    |> Enum.find(fn profile ->
      MapSet.member?(needles, String.downcase(Profile.dispatch_label(profile)))
    end)
    |> case do
      nil -> {:error, :no_matching_profile}
      profile -> {:ok, profile}
    end
  end

  defp count_for_account(account_id) do
    Profile
    |> where([p], p.account_id == ^account_id)
    |> Repo.aggregate(:count, :id)
  end

  defp stringify_keys(map) when is_map(map) do
    Map.new(map, fn
      {k, v} when is_atom(k) -> {Atom.to_string(k), v}
      {k, v} -> {k, v}
    end)
  end
end

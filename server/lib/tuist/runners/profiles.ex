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
  Create a profile under `account`. The catalog data passed into the
  schema validation is keyed off the profile's `platform`:

    * Linux profiles validate against `Catalog.shapes(:linux)`.
    * macOS profiles validate against `Catalog.shapes(:macos)` plus
      `Catalog.xcode_versions/0`.

  Per-account cap applies across platforms.
  """
  def create(%{id: account_id}, attrs) do
    attrs = Map.put(stringify_keys(attrs), "account_id", account_id)

    if count_for_account(account_id) >= @max_per_account do
      {:error, :max_profiles_reached}
    else
      %Profile{}
      |> Profile.changeset(attrs, catalog_opts_for(parse_platform(attrs)))
      |> Repo.insert()
    end
  end

  @doc """
  The auto-bootstrapped Linux profile name. Surfaced so callers can
  reason about which row is "the default" without re-encoding the
  string.
  """
  def default_linux_name, do: "linux"

  @doc """
  The auto-bootstrapped macOS profile name. Parallel to
  `default_linux_name/0`.
  """
  def default_macos_name, do: "macos"

  @doc """
  Insert the per-account protected `linux` profile, matching the
  catalog default shape so `runs-on: <prefix>linux` always lands on
  the warm pool. Idempotent — a no-op when a row with the same name
  already exists, since `name` is the unique key per account.

  Called from `Accounts.create_user` / `Accounts.create_organization`
  inside the same Multi as the Account insert; failing here aborts
  the whole transaction so no account ever lands without its default
  profile. The per-account `@max_per_account` cap is intentionally
  bypassed — the customer didn't create this row.
  """
  def create_default_for_account(%{id: account_id}) do
    case Catalog.default_shape(:linux) do
      nil ->
        {:error, :no_catalog_default}

      default ->
        attrs = %{
          "account_id" => account_id,
          "name" => default_linux_name(),
          "platform" => "linux",
          "vcpus" => default.vcpus,
          "memory_gb" => default.memory_gb,
          "protected" => true
        }

        %Profile{}
        |> Profile.changeset(attrs, catalog_opts_for(:linux))
        |> Repo.insert(on_conflict: :nothing, conflict_target: [:account_id, :name])
    end
  end

  @doc """
  Same as `create_default_for_account/1`, for macOS. Inserts the
  protected `macos` profile carrying the catalog default shape +
  Xcode version so `runs-on: <prefix>macos` always lands on the warm
  macOS pool. Idempotent — a no-op when a `macos` row already exists
  for the account.

  Called alongside `create_default_for_account/1` from
  `Accounts.create_user` / `Accounts.create_organization` inside the
  same Multi. Failing here aborts the whole account-creation
  transaction — every account always has both a Linux and a macOS
  protected profile so the env's default `tuist-…-linux` /
  `tuist-…-macos` labels always resolve.
  """
  def create_default_macos_for_account(%{id: account_id}) do
    with default_shape when not is_nil(default_shape) <- Catalog.default_shape(:macos),
         default_xcode when not is_nil(default_xcode) <- Catalog.default_xcode_version() do
      attrs = %{
        "account_id" => account_id,
        "name" => default_macos_name(),
        "platform" => "macos",
        "vcpus" => default_shape.vcpus,
        "memory_gb" => default_shape.memory_gb,
        "xcode_version" => default_xcode.xcode_version,
        "protected" => true
      }

      %Profile{}
      |> Profile.changeset(attrs, catalog_opts_for(:macos))
      |> Repo.insert(on_conflict: :nothing, conflict_target: [:account_id, :name])
    else
      # Self-hosted servers without a macOS runner catalog (no fleet,
      # tests without the macos stubs) skip the macOS protected
      # profile rather than aborting the account-creation Multi. The
      # account just won't have a default macOS dispatch target;
      # `tuist-…-macos` labels will return RunnerNotFound until an
      # operator wires the catalog.
      _ -> {:ok, :no_macos_capable}
    end
  end

  @doc """
  Update a profile's resources. `name` and `platform` cannot change
  post-create (see module docs). Passing either is silently ignored.
  """
  def update(%Profile{platform: platform} = profile, attrs) do
    attrs =
      attrs
      |> stringify_keys()
      |> Map.drop(["name", "account_id", "platform"])

    profile
    |> Profile.changeset(attrs, catalog_opts_for(platform))
    |> Repo.update()
  end

  @doc """
  Delete a profile. Workflows still referencing it will hit
  `:no_matching_profile` on their next dispatch; in-flight Pods
  already claimed against the corresponding shape pool finish
  normally (the shape pool isn't going anywhere).

  Protected profiles (the per-account `linux` default) refuse
  deletion — every account always has a Linux profile so the
  `<prefix>linux` label always resolves.
  """
  def delete(%Profile{protected: true}), do: {:error, :protected}
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

  defp parse_platform(%{"platform" => "linux"}), do: :linux
  defp parse_platform(%{"platform" => "macos"}), do: :macos
  defp parse_platform(%{"platform" => :linux}), do: :linux
  defp parse_platform(%{"platform" => :macos}), do: :macos
  # Mirror the schema default: an unset platform attr means Linux.
  defp parse_platform(_), do: :linux

  defp catalog_opts_for(:linux), do: [shapes: Catalog.shapes(:linux)]

  defp catalog_opts_for(:macos),
    do: [shapes: Catalog.shapes(:macos), xcode_versions: Catalog.xcode_versions()]
end

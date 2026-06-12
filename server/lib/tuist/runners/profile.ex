defmodule Tuist.Runners.Profile do
  @moduledoc """
  Account-scoped Runner Profile. Customers reference the profile in
  GitHub Actions workflows as `runs-on: <prefix><name>` — see
  `prefix/0` — and the dispatch path resolves
  `(account, requested-label)` through the profile to the matching
  pool.

  Profiles are platform-specific. The dimensions that vary by
  platform:

    * `:linux` — `(vcpus, memory_gb)`, picked from
      `Tuist.Runners.Catalog.shapes(:linux)`.
    * `:macos` — `(vcpus, memory_gb)` plus an `xcode_version`,
      picked from `Catalog.shapes(:macos)` (M2-L is the only shape
      today) and `Catalog.xcode_versions/0`. The Xcode
      version pins the runner image's `:macos-<dashes>-<semver>`
      tag.

  Backed by [priv/repo/migrations/20260527130000_create_runner_profiles.exs](priv/repo/migrations/20260527130000_create_runner_profiles.exs)
  and [priv/repo/migrations/20260602144624_add_platform_and_xcode_to_runner_profiles.exs](priv/repo/migrations/20260602144624_add_platform_and_xcode_to_runner_profiles.exs).
  """
  use Ecto.Schema

  import Ecto.Changeset

  alias Tuist.Accounts.Account
  alias Tuist.Environment

  @name_format ~r/^[a-z][a-z0-9-]{0,31}$/

  # `runner` / `runners` / `tuist` keep the dispatch-label
  # prefix namespace clean (e.g. `runs-on: tuist-tuist`).
  @reserved_names ~w(runner runners tuist)

  @platforms [:linux, :macos]

  schema "runner_profiles" do
    field :name, :string
    # Default `:linux` matches the migration's column default and
    # keeps Linux-only callers (the LiveView form, tests, the per-
    # account bootstrap) working without threading platform through
    # every attrs map. macOS callers must set it explicitly.
    field :platform, Ecto.Enum, values: @platforms, default: :linux
    field :vcpus, :integer
    field :memory_gb, :integer
    field :xcode_version, :string
    field :protected, :boolean, default: false

    belongs_to :account, Account

    timestamps(type: :utc_datetime)
  end

  @doc """
  All supported platforms.
  """
  def platforms, do: @platforms

  @doc """
  Changeset for create / update.

  `opts` carries the catalog data the schema validates against. The
  schema doesn't touch `Tuist.Runners.Catalog` directly so tests can
  drive validation with a fixed catalog without mocking module-level
  Application config:

    * `:shapes` — the `(vcpus, memory_gb)` list for *this profile's
      platform*. Required.
    * `:xcode_versions` — list of supported Xcode versions. Only
      consulted for macOS profiles; ignored for Linux.
  """
  def changeset(profile, attrs, opts \\ []) when is_list(opts) do
    shapes = Keyword.get(opts, :shapes, [])
    xcode_versions = Keyword.get(opts, :xcode_versions, [])

    changeset =
      profile
      |> cast(attrs, [
        :account_id,
        :name,
        :platform,
        :vcpus,
        :memory_gb,
        :xcode_version,
        :protected
      ])
      |> validate_required([:account_id, :name, :platform, :vcpus, :memory_gb])
      |> update_change(:name, &normalize_name/1)
      |> validate_format(:name, @name_format,
        message: "must start with a letter and contain only lowercase letters, digits, and hyphens"
      )
      |> validate_length(:name, max: 32)
      |> validate_exclusion(:name, @reserved_names)
      |> unique_constraint([:account_id, :name],
        message: "a profile with this name already exists in this account"
      )
      |> foreign_key_constraint(:account_id)

    case get_field(changeset, :platform) do
      :linux ->
        changeset
        |> put_change(:xcode_version, nil)
        |> validate_shape(shapes)

      :macos ->
        changeset
        |> validate_required([:xcode_version])
        |> validate_shape(shapes)
        |> validate_xcode_version(xcode_versions)

      _ ->
        changeset
    end
  end

  defp normalize_name(nil), do: nil
  defp normalize_name(name) when is_binary(name), do: name |> String.trim() |> String.downcase()

  defp validate_shape(changeset, catalog) do
    vcpus = get_field(changeset, :vcpus)
    memory_gb = get_field(changeset, :memory_gb)

    cond do
      is_nil(vcpus) or is_nil(memory_gb) ->
        changeset

      Enum.any?(catalog, fn shape -> shape.vcpus == vcpus and shape.memory_gb == memory_gb end) ->
        changeset

      true ->
        add_error(changeset, :vcpus, "must match one of the available resource configurations")
    end
  end

  defp validate_xcode_version(changeset, catalog) do
    xcode_version = get_field(changeset, :xcode_version)

    cond do
      is_nil(xcode_version) ->
        changeset

      Enum.any?(catalog, fn xcode -> xcode.xcode_version == xcode_version end) ->
        changeset

      true ->
        add_error(changeset, :xcode_version, "must match one of the available Xcode versions")
    end
  end

  @doc """
  The `runs-on:` prefix every profile-routed label carries on this
  deployment. Production stays plain `tuist-` for the simplest
  customer-visible form; non-production envs add the env name so
  the shared GitHub App installation cannot cross-route between
  envs (staging's `tuist-staging-foo` and production's `tuist-foo`
  occupy disjoint label namespaces).
  """
  def prefix do
    case Environment.env() do
      :stag -> "tuist-staging-"
      :can -> "tuist-canary-"
      _ -> "tuist-"
    end
  end

  @doc """
  The customer-facing label this profile resolves from in
  `runs-on:`. Stable for a profile's lifetime since `name` is
  immutable post-create (see `Profiles.update/2`).
  """
  def dispatch_label(%__MODULE__{name: name}) when is_binary(name) and name != "" do
    prefix() <> name
  end
end

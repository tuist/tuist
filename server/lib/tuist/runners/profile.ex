defmodule Tuist.Runners.Profile do
  @moduledoc """
  Account-scoped Runner Profile. Customers reference the profile in
  GitHub Actions workflows as `runs-on: tuist-<name>`, and the
  dispatch path resolves `(account, requested-label)` through the
  profile to the matching shape pool.

  Backed by [priv/repo/migrations/20260527130000_create_runner_profiles.exs](priv/repo/migrations/20260527130000_create_runner_profiles.exs).
  """
  use Ecto.Schema

  import Ecto.Changeset

  alias Tuist.Accounts.Account

  @name_format ~r/^[a-z][a-z0-9-]{0,31}$/

  # `linux` and `macos` are reserved so we can introduce a
  # cross-account "default per platform" preset later without a
  # migration. `runner` / `runners` / `tuist` keep the prefix
  # namespace clean.
  @reserved_names ~w(linux macos runner runners tuist)

  schema "runner_profiles" do
    field :name, :string
    field :vcpus, :integer
    field :memory_gb, :integer

    belongs_to :account, Account

    timestamps(type: :utc_datetime)
  end

  @doc """
  Changeset for create / update. `catalog` is the list of
  `(vcpus, memory_gb)` pairs the shape catalog currently exposes,
  passed in by the caller (the schema is intentionally unaware of
  the K8s side).
  """
  def changeset(profile, attrs, catalog) when is_list(catalog) do
    profile
    |> cast(attrs, [:account_id, :name, :vcpus, :memory_gb])
    |> validate_required([:account_id, :name, :vcpus, :memory_gb])
    |> update_change(:name, &normalize_name/1)
    |> validate_format(:name, @name_format,
      message: "must start with a letter and contain only lowercase letters, digits, and hyphens"
    )
    |> validate_length(:name, max: 32)
    |> validate_exclusion(:name, @reserved_names)
    |> validate_shape(catalog)
    |> unique_constraint([:account_id, :name],
      message: "a profile with this name already exists in this account"
    )
    |> foreign_key_constraint(:account_id)
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

  @doc """
  The customer-facing label this profile resolves from in
  `runs-on:`. Stable for a profile's lifetime since `name` is
  immutable post-create (see `Profiles.update/2`).
  """
  def dispatch_label(%__MODULE__{name: name}) when is_binary(name) and name != "" do
    "tuist-" <> name
  end
end

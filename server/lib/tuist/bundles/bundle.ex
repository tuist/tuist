defmodule Tuist.Bundles.Bundle do
  @moduledoc """
  ClickHouse-backed schema for app bundles.
  """

  use Ecto.Schema

  import Ecto.Changeset

  alias Tuist.Bundles.Artifact

  @platforms [
    :ios,
    :ios_simulator,
    :tvos,
    :tvos_simulator,
    :watchos,
    :watchos_simulator,
    :visionos,
    :visionos_simulator,
    :macos,
    :android
  ]

  @types [:ipa, :app, :xcarchive, :aab, :apk]

  @platform_strings Enum.map(@platforms, &Atom.to_string/1)
  @type_strings Enum.map(@types, &Atom.to_string/1)

  @derive {
    Flop.Schema,
    filterable: [
      :project_id,
      :git_branch,
      :type,
      :name,
      :install_size,
      :download_size,
      :supported_platforms,
      :inserted_at
    ],
    sortable: [:inserted_at, :install_size, :download_size]
  }

  @primary_key {:id, Ch, type: "UUID", autogenerate: false}
  schema "bundles" do
    field :app_bundle_id, Ch, type: "String"
    field :name, Ch, type: "String"
    field :install_size, Ch, type: "Int64"
    field :download_size, Ch, type: "Nullable(Int64)"
    field :git_branch, Ch, type: "Nullable(String)"
    field :git_commit_sha, Ch, type: "Nullable(String)"
    field :git_ref, Ch, type: "Nullable(String)"
    field :supported_platforms, Ch, type: "Array(LowCardinality(String))"
    field :version, Ch, type: "String"
    field :type, Ch, type: "LowCardinality(String)"
    field :project_id, Ch, type: "Int64"
    field :uploaded_by_account_id, Ch, type: "Nullable(Int64)"

    field :inserted_at, Ch, type: "DateTime64(6)"
    field :updated_at, Ch, type: "DateTime64(6)"

    belongs_to :project, Tuist.Projects.Project, type: :integer, define_field: false

    belongs_to :uploaded_by_account, Tuist.Accounts.Account,
      type: :integer,
      define_field: false

    has_many :artifacts, Artifact, foreign_key: :bundle_id
  end

  @doc """
  Atom values accepted as `type` on bundle uploads.
  """
  def types, do: @types

  @doc """
  Atom values accepted in `supported_platforms` on bundle uploads.
  """
  def supported_platforms, do: @platforms

  @doc """
  Validates input attrs and returns a changeset suitable for inserting
  the bundle row into ClickHouse.

  `type` and `supported_platforms` are accepted as atoms (internal
  callers, fixtures) or strings (controller, post-OpenAPI cast); they
  are normalized to strings before cast since the backing columns are
  `LowCardinality(String)` / `Array(LowCardinality(String))`.

  `inserted_at` / `updated_at` accept `DateTime` or `NaiveDateTime`;
  both are normalized to microsecond-precision `NaiveDateTime` for
  the `DateTime64(6)` columns.
  """
  def create_changeset(bundle \\ %__MODULE__{}, attrs) do
    attrs
    |> normalize_atom(:type)
    |> normalize_atom_list(:supported_platforms)
    |> normalize_naive_datetime(:inserted_at)
    |> normalize_naive_datetime(:updated_at)
    |> then(fn attrs ->
      bundle
      |> cast(attrs, [
        :id,
        :app_bundle_id,
        :name,
        :install_size,
        :download_size,
        :supported_platforms,
        :version,
        :type,
        :project_id,
        :uploaded_by_account_id,
        :git_commit_sha,
        :git_branch,
        :git_ref,
        :inserted_at,
        :updated_at
      ])
      |> validate_required([
        :id,
        :app_bundle_id,
        :name,
        :install_size,
        :supported_platforms,
        :version,
        :type,
        :project_id
      ])
      |> validate_inclusion(:type, @type_strings)
      |> validate_supported_platforms()
    end)
  end

  # Hand-rolled instead of `validate_subset/3` because that helper
  # introspects the field's Ecto type to confirm it's `{:array, _}`,
  # and the parameterized `Ch, type: "Array(LowCardinality(String))"`
  # type doesn't match that shape so the helper crashes on cast.
  defp validate_supported_platforms(changeset) do
    validate_change(changeset, :supported_platforms, fn :supported_platforms, values ->
      case Enum.reject(values, &(&1 in @platform_strings)) do
        [] -> []
        _invalid -> [supported_platforms: "has an invalid entry"]
      end
    end)
  end

  defp normalize_atom(attrs, field) do
    case Map.get(attrs, field) do
      value when is_atom(value) and not is_nil(value) ->
        Map.put(attrs, field, Atom.to_string(value))

      _ ->
        attrs
    end
  end

  defp normalize_atom_list(attrs, field) do
    case Map.get(attrs, field) do
      values when is_list(values) ->
        Map.put(
          attrs,
          field,
          Enum.map(values, fn
            v when is_atom(v) -> Atom.to_string(v)
            v -> v
          end)
        )

      _ ->
        attrs
    end
  end

  defp normalize_naive_datetime(attrs, field) do
    case Map.get(attrs, field) do
      %DateTime{} = dt ->
        Map.put(attrs, field, dt |> DateTime.to_naive() |> bump_usec_precision())

      %NaiveDateTime{} = ndt ->
        Map.put(attrs, field, bump_usec_precision(ndt))

      _ ->
        attrs
    end
  end

  defp bump_usec_precision(%NaiveDateTime{microsecond: {value, _}} = ndt) do
    %{ndt | microsecond: {value, 6}}
  end
end

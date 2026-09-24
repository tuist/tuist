defmodule Atlas.Assets.DataCenter do
  @moduledoc """
  A colocation facility or private data center that hosts one or more assets.

  Only the coarse-grained facility is modeled here. Rack and U-position land
  in a follow-up once the fleet warrants more than one rack.
  """

  use Atlas.Schema

  import Ecto.Changeset

  alias Atlas.Assets.Asset
  alias Atlas.Assets.DataCenter

  @statuses ~w(active decommissioned)

  @creation_fields ~w(name provider city country notes)a
  @metadata_fields @creation_fields

  @derive {
    Flop.Schema,
    filterable: [:status, :provider, :country],
    sortable: [:name, :provider, :city, :country, :status, :inserted_at],
    default_limit: 50,
    max_limit: 200
  }

  schema "asset_data_centers" do
    field :name, :string
    field :provider, :string
    field :city, :string
    field :country, :string
    field :notes, :string
    field :status, :string, default: "active"

    has_many :assets, Asset, foreign_key: :data_center_id

    timestamps()
  end

  def statuses, do: @statuses

  def create_changeset(%DataCenter{} = data_center, attrs) do
    data_center
    |> cast(attrs, @creation_fields)
    |> validate_required([:name])
    |> common_validations()
  end

  def metadata_changeset(%DataCenter{} = data_center, attrs) do
    data_center
    |> cast(attrs, @metadata_fields)
    |> common_validations()
  end

  def status_changeset(%DataCenter{} = data_center, attrs) do
    data_center
    |> cast(attrs, [:status])
    |> validate_required([:status])
    |> validate_inclusion(:status, @statuses)
    |> translate_db_checks()
  end

  defp common_validations(changeset) do
    changeset
    |> update_change(:name, &normalize_optional_string/1)
    |> update_change(:provider, &normalize_optional_string/1)
    |> update_change(:city, &normalize_optional_string/1)
    |> update_change(:country, &normalize_optional_string/1)
    |> validate_required([:name])
    |> unique_constraint(:name, name: :asset_data_centers_name_index)
    |> translate_db_checks()
  end

  defp translate_db_checks(changeset) do
    check_constraint(changeset, :status,
      name: :asset_data_centers_status_check,
      message: "is not a valid status"
    )
  end

  defp normalize_optional_string(nil), do: nil

  defp normalize_optional_string(value) when is_binary(value) do
    case String.trim(value) do
      "" -> nil
      trimmed -> trimmed
    end
  end
end

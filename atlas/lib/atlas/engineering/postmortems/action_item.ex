defmodule Atlas.Engineering.Postmortems.ActionItem do
  @moduledoc false

  use Ecto.Schema

  import Ecto.Changeset

  alias Atlas.Engineering.Postmortems.Postmortem

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  @priorities [:immediate, :high, :medium, :low]

  schema "postmortem_action_items" do
    field :title, :string
    field :description, :string
    field :resolution_url, :string
    field :priority, Ecto.Enum, values: @priorities, default: :medium
    field :completed_at, :utc_datetime

    belongs_to :postmortem, Postmortem

    timestamps(type: :utc_datetime)
  end

  def priorities, do: @priorities

  def changeset(action_item, attrs) do
    action_item
    |> cast(attrs, [:title, :description, :resolution_url, :priority])
    |> validate_required([:title, :priority])
    |> validate_length(:title, min: 3, max: 500)
    |> validate_length(:description, max: 5_000)
    |> validate_length(:resolution_url, max: 2_048)
    |> validate_url(:resolution_url)
    |> validate_inclusion(:priority, @priorities)
    |> foreign_key_constraint(:postmortem_id)
    |> check_constraint(:priority, name: :postmortem_action_items_priority_check)
  end

  defp validate_url(changeset, field) do
    validate_change(changeset, field, fn ^field, url ->
      case URI.new(url) do
        {:ok, %URI{scheme: scheme, host: host}}
        when scheme in ["http", "https"] and is_binary(host) and host != "" ->
          []

        _ ->
          [{field, "must be a valid HTTP or HTTPS URL"}]
      end
    end)
  end
end

defmodule Atlas.Audit.Activity do
  use Atlas.Schema

  import Ecto.Changeset

  alias Atlas.Users.User

  @interfaces ~w(dashboard mcp slack api worker system)
  @string_fields [
    :action,
    :interface,
    :actor_email,
    :actor_name,
    :actor_role,
    :target_type,
    :target_id,
    :target_label
  ]

  @derive {
    Flop.Schema,
    filterable: [:action, :interface, :actor_id, :actor_email, :target_type, :target_id],
    sortable: [:occurred_at, :inserted_at],
    default_limit: 25,
    max_limit: 100
  }

  schema "audit_activities" do
    field :action, :string
    field :interface, :string
    field :occurred_at, :utc_datetime
    field :actor_email, :string
    field :actor_name, :string
    field :actor_role, :string
    field :target_type, :string
    field :target_id, :string
    field :target_label, :string
    field :metadata, :map, default: %{}

    belongs_to :actor, User

    timestamps()
  end

  def interfaces, do: @interfaces

  def changeset(activity, attrs) do
    activity
    |> cast(attrs, [
      :action,
      :interface,
      :occurred_at,
      :actor_id,
      :actor_email,
      :actor_name,
      :actor_role,
      :target_type,
      :target_id,
      :target_label,
      :metadata
    ])
    |> put_default_occurred_at()
    |> normalize_string_fields()
    |> validate_required([:action, :interface, :occurred_at])
    |> validate_inclusion(:interface, @interfaces)
    |> foreign_key_constraint(:actor_id)
  end

  defp put_default_occurred_at(changeset) do
    case get_field(changeset, :occurred_at) do
      nil -> put_change(changeset, :occurred_at, DateTime.utc_now() |> DateTime.truncate(:second))
      _occurred_at -> changeset
    end
  end

  defp normalize_string_fields(changeset) do
    Enum.reduce(@string_fields, changeset, fn field, changeset ->
      update_change(changeset, field, &normalize_string/1)
    end)
  end

  defp normalize_string(nil), do: nil

  defp normalize_string(value) when is_binary(value) do
    value
    |> String.trim()
    |> case do
      "" -> nil
      trimmed -> trimmed
    end
  end

  defp normalize_string(value), do: to_string(value)
end

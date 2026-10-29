defmodule Atlas.Granola.NoteIngestion do
  use Atlas.Schema

  import Ecto.Changeset

  alias Atlas.Accounts.Event

  @statuses ~w(captured ignored)

  def statuses, do: @statuses

  schema "granola_note_ingestions" do
    field :external_id, :string
    field :note_updated_at, :utc_datetime
    field :status, :string
    field :ignore_reason, :string
    field :metadata, :map, default: %{}

    belongs_to :account_event, Event

    timestamps()
  end

  def changeset(note_ingestion, attrs) do
    note_ingestion
    |> cast(attrs, [
      :external_id,
      :note_updated_at,
      :status,
      :ignore_reason,
      :account_event_id,
      :metadata
    ])
    |> normalize_string_fields([:external_id, :status, :ignore_reason])
    |> validate_required([:external_id, :status])
    |> validate_inclusion(:status, @statuses)
    |> unique_constraint(:external_id)
    |> foreign_key_constraint(:account_event_id)
  end

  defp normalize_string_fields(changeset, fields) do
    Enum.reduce(fields, changeset, &normalize_string_field/2)
  end

  defp normalize_string_field(field, changeset) do
    update_change(changeset, field, fn
      nil ->
        nil

      value when is_binary(value) ->
        value
        |> String.trim()
        |> case do
          "" -> nil
          normalized -> normalized
        end

      value ->
        value
    end)
  end
end

defmodule Atlas.Search.Record do
  use Atlas.Schema

  import Ecto.Changeset

  alias Atlas.Accounts.Account

  @source_types ~w(
    account_event
    account_outcome
    account_overview_summary
    blog_post_idea
    gtm_opportunity
    gtm_signal
    social_channel_idea
    note
  )

  def source_types, do: @source_types

  schema "search_records" do
    field :source_type, :string
    field :source_id, :string
    field :title, :string
    field :body, :string
    field :path, :string
    field :metadata, :map, default: %{}
    field :embedding_model, :string
    field :embedded_at, :utc_datetime

    belongs_to :account, Account

    timestamps()
  end

  def changeset(record, attrs) do
    record
    |> cast(attrs, [:source_type, :source_id, :title, :body, :path, :metadata])
    |> normalize_string_fields([:source_type, :source_id, :title, :body, :path])
    |> validate_required([:source_type, :source_id, :title])
    |> validate_inclusion(:source_type, @source_types)
    |> unique_constraint([:source_type, :source_id])
    |> foreign_key_constraint(:account_id)
  end

  def embedding_changeset(record, model, %DateTime{} = embedded_at) when is_binary(model) do
    record
    |> change()
    |> put_change(:embedding_model, model)
    |> put_change(:embedded_at, DateTime.truncate(embedded_at, :second))
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

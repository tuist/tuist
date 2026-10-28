defmodule Atlas.GTM.SignalQuery do
  use Atlas.Schema

  import Ecto.Changeset

  @sources ~w(brave github)

  def sources, do: @sources

  schema "gtm_signal_queries" do
    field :name, :string
    field :source, :string
    field :query, :string
    field :enabled, :boolean, default: true
    field :result_limit, :integer, default: 5
    field :metadata, :map, default: %{}
    field :last_run_at, :utc_datetime

    timestamps()
  end

  def changeset(query, attrs) do
    query
    |> cast(attrs, [:name, :source, :query, :enabled, :result_limit, :metadata, :last_run_at])
    |> normalize_string_fields([:name, :source, :query])
    |> validate_required([:name, :source, :query, :result_limit])
    |> validate_inclusion(:source, @sources)
    |> validate_number(:result_limit, greater_than: 0, less_than_or_equal_to: 25)
    |> unique_constraint([:source, :query], name: :gtm_signal_queries_source_query_index)
  end

  def mark_run_changeset(query, now) do
    change(query, last_run_at: DateTime.truncate(now, :second))
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

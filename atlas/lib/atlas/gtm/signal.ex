defmodule Atlas.GTM.Signal do
  use Atlas.Schema

  import Ecto.Changeset

  alias Atlas.GTM.Opportunity
  alias Atlas.GTM.SignalQuery

  @sources ~w(brave github apollo manual)
  @signal_kinds ~w(build_system engineering_blog github_repository hiring platform_engineering developer_productivity ci_scale tuist_mention manual)

  def sources, do: @sources
  def signal_kinds, do: @signal_kinds

  schema "gtm_signals" do
    field :source, :string
    field :source_ref, :string
    field :source_url, :string
    field :title, :string
    field :excerpt, :string
    field :matched_terms, {:array, :string}, default: []
    field :signal_kind, :string
    field :confidence, :integer, default: 0
    field :observed_at, :utc_datetime
    field :metadata, :map, default: %{}

    belongs_to :query, SignalQuery
    belongs_to :opportunity, Opportunity

    timestamps()
  end

  def changeset(signal, attrs) do
    signal
    |> cast(attrs, [
      :source,
      :source_ref,
      :source_url,
      :title,
      :excerpt,
      :matched_terms,
      :signal_kind,
      :confidence,
      :observed_at,
      :metadata,
      :query_id,
      :opportunity_id
    ])
    |> normalize_string_fields([:source, :source_ref, :source_url, :title, :excerpt, :signal_kind])
    |> normalize_matched_terms()
    |> validate_required([:source, :source_ref, :title, :signal_kind, :confidence, :observed_at, :opportunity_id])
    |> validate_inclusion(:source, @sources)
    |> validate_inclusion(:signal_kind, @signal_kinds)
    |> validate_number(:confidence, greater_than_or_equal_to: 0, less_than_or_equal_to: 100)
    |> unique_constraint([:source, :source_ref], name: :gtm_signals_source_source_ref_index)
    |> foreign_key_constraint(:query_id)
    |> foreign_key_constraint(:opportunity_id)
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

  defp normalize_matched_terms(changeset) do
    update_change(changeset, :matched_terms, fn
      terms when is_list(terms) ->
        terms
        |> Enum.filter(&is_binary/1)
        |> Enum.map(&String.trim/1)
        |> Enum.reject(&(&1 == ""))
        |> Enum.uniq()

      _terms ->
        []
    end)
  end
end

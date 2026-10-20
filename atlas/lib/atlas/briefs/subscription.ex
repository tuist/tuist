defmodule Atlas.Briefs.Subscription do
  use Atlas.Schema

  import Ecto.Changeset

  alias Atlas.Briefs.Brief

  @cadences ~w(daily weekly monthly)
  @domains ~w(finance accounts outreach product company)
  @sensitivities ~w(public internal restricted)

  schema "brief_subscriptions" do
    field :label, :string
    field :audience_key, :string
    field :cadence, :string
    field :domains, {:array, :string}, default: []
    field :slack_app, :string, default: "company"
    field :slack_channel_id, :string
    field :max_sensitivity, :string, default: "restricted"
    field :attention_budget, :integer, default: 8
    field :enabled, :boolean, default: true

    has_many :briefs, Brief, foreign_key: :brief_subscription_id

    timestamps()
  end

  def cadences, do: @cadences
  def domains, do: @domains

  def changeset(subscription, attrs) do
    subscription
    |> cast(attrs, [
      :label,
      :audience_key,
      :cadence,
      :domains,
      :slack_app,
      :slack_channel_id,
      :max_sensitivity,
      :attention_budget,
      :enabled
    ])
    |> normalize_strings()
    |> validate_required([
      :label,
      :audience_key,
      :cadence,
      :domains,
      :slack_app,
      :slack_channel_id,
      :max_sensitivity,
      :attention_budget,
      :enabled
    ])
    |> validate_inclusion(:cadence, @cadences)
    |> validate_inclusion(:max_sensitivity, @sensitivities)
    |> validate_subset(:domains, @domains)
    |> validate_length(:domains, min: 1)
    |> validate_number(:attention_budget, greater_than: 0, less_than_or_equal_to: 20)
    |> unique_constraint([:audience_key, :cadence])
    |> check_constraint(:cadence, name: :brief_subscriptions_cadence_check)
    |> check_constraint(:max_sensitivity, name: :brief_subscriptions_sensitivity_check)
    |> check_constraint(:attention_budget, name: :brief_subscriptions_budget_check)
    |> check_constraint(:domains, name: :brief_subscriptions_domains_check)
  end

  defp normalize_strings(changeset) do
    Enum.reduce(
      [:label, :audience_key, :cadence, :slack_app, :slack_channel_id, :max_sensitivity],
      changeset,
      fn field, changeset -> update_change(changeset, field, &normalize_string/1) end
    )
  end

  defp normalize_string(nil), do: nil
  defp normalize_string(value) when is_binary(value), do: String.trim(value)
  defp normalize_string(value), do: value
end

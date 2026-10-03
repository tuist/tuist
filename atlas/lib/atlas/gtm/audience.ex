defmodule Atlas.GTM.Audience do
  use Atlas.Schema

  import Ecto.Changeset

  alias Atlas.GTM.AudienceMembership
  alias Atlas.GTM.Broadcast

  @membership_types ~w(static dynamic)
  @account_segments ~w(customer lead prospect)
  @hosting_values ~w(all self_hosted)
  @recipient_sources ~w(account_contacts incident_contacts)
  @contacts_per_account_values ~w(all one)

  @derive {
    Flop.Schema,
    filterable: [:source_id], sortable: [:name, :inserted_at], default_limit: 25, max_limit: 100
  }

  schema "gtm_audiences" do
    field :name, :string
    field :slug, :string
    field :description, :string
    field :source_id, :string
    field :membership_type, :string, default: "static"
    field :rules, :map, default: %{}
    field :subscribers_count, :integer, virtual: true, default: 0
    field :broadcasts_count, :integer, virtual: true, default: 0

    has_many :memberships, AudienceMembership
    has_many :subscribers, through: [:memberships, :subscriber]
    has_many :broadcasts, Broadcast

    timestamps()
  end

  def changeset(audience, attrs) do
    audience
    |> cast(attrs, [:name, :slug, :description, :source_id, :membership_type, :rules])
    |> normalize_fields()
    |> normalize_rules()
    |> validate_required([:name, :slug])
    |> validate_inclusion(:membership_type, @membership_types)
    |> validate_dynamic_rules()
    |> unique_constraint(:slug)
    |> unique_constraint(:source_id)
  end

  def membership_types, do: @membership_types
  def account_segments, do: @account_segments
  def hosting_values, do: @hosting_values
  def recipient_sources, do: @recipient_sources
  def contacts_per_account_values, do: @contacts_per_account_values

  def dynamic?(%__MODULE__{membership_type: "dynamic"}), do: true
  def dynamic?(_audience), do: false

  defp normalize_fields(changeset) do
    Enum.reduce([:name, :slug, :description, :source_id, :membership_type], changeset, fn field, changeset ->
      update_change(changeset, field, &normalize_string/1)
    end)
  end

  defp normalize_rules(changeset) do
    rules = Ecto.Changeset.get_field(changeset, :rules)

    normalized_rules =
      case rules do
        rules when is_map(rules) ->
          %{
            "account_segment" => normalized_rule(rules, "account_segment", "customer"),
            "hosting" => normalized_rule(rules, "hosting", "all"),
            "recipient_source" => normalized_rule(rules, "recipient_source", "account_contacts"),
            "contacts_per_account" => normalized_rule(rules, "contacts_per_account", "all")
          }

        _rules ->
          %{}
      end

    put_change(changeset, :rules, normalized_rules)
  end

  defp validate_dynamic_rules(changeset) do
    if get_field(changeset, :membership_type) == "dynamic" do
      rules = get_field(changeset, :rules) || %{}
      account_segment = Map.get(rules, "account_segment")
      hosting = Map.get(rules, "hosting")
      recipient_source = Map.get(rules, "recipient_source")
      contacts_per_account = Map.get(rules, "contacts_per_account")

      changeset
      |> maybe_add_rule_error(account_segment in @account_segments, "has an invalid account lifecycle")
      |> maybe_add_rule_error(hosting in @hosting_values, "has an invalid hosting filter")
      |> maybe_add_rule_error(recipient_source in @recipient_sources, "has an invalid recipient source")
      |> maybe_add_rule_error(
        contacts_per_account in @contacts_per_account_values,
        "has an invalid contacts-per-account setting"
      )
    else
      put_change(changeset, :rules, %{})
    end
  end

  defp normalized_rule(rules, key, default) do
    rules
    |> Map.get(key, Map.get(rules, rule_atom(key), default))
    |> normalize_string()
    |> case do
      nil -> default
      value -> value
    end
  end

  defp rule_atom("account_segment"), do: :account_segment
  defp rule_atom("hosting"), do: :hosting
  defp rule_atom("recipient_source"), do: :recipient_source
  defp rule_atom("contacts_per_account"), do: :contacts_per_account

  defp maybe_add_rule_error(changeset, true, _message), do: changeset
  defp maybe_add_rule_error(changeset, false, message), do: add_error(changeset, :rules, message)

  defp normalize_string(nil), do: nil

  defp normalize_string(value) do
    value
    |> String.trim()
    |> case do
      "" -> nil
      trimmed -> trimmed
    end
  end
end

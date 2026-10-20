defmodule Atlas.Briefs.Suppression do
  use Atlas.Schema

  import Ecto.Changeset

  alias Atlas.Briefs.BriefItem
  alias Atlas.Briefs.Subscription
  alias Atlas.Users.User

  schema "brief_suppressions" do
    field :domain, :string
    field :fingerprint, :string
    field :reason, :string
    field :suppressed_until, :utc_datetime
    field :severity, :string

    belongs_to :subscription, Subscription, foreign_key: :brief_subscription_id
    belongs_to :created_by, User
    belongs_to :source_brief_item, BriefItem

    timestamps()
  end

  def changeset(suppression, attrs) do
    suppression
    |> cast(attrs, [
      :domain,
      :fingerprint,
      :reason,
      :suppressed_until,
      :severity,
      :brief_subscription_id,
      :created_by_id,
      :source_brief_item_id
    ])
    |> update_change(:domain, &normalize_string/1)
    |> update_change(:fingerprint, &normalize_string/1)
    |> update_change(:reason, &normalize_string/1)
    |> validate_required([:brief_subscription_id, :domain, :fingerprint, :reason])
    |> validate_inclusion(:domain, BriefItem.domains())
    |> validate_inclusion(:severity, BriefItem.severities())
    |> foreign_key_constraint(:brief_subscription_id)
    |> foreign_key_constraint(:created_by_id)
    |> foreign_key_constraint(:source_brief_item_id)
    |> unique_constraint([:brief_subscription_id, :domain, :fingerprint],
      name: :brief_suppressions_brief_subscription_id_domain_fingerprint_ind
    )
    |> check_constraint(:domain, name: :brief_suppressions_domain_check)
    |> check_constraint(:severity, name: :brief_suppressions_severity_check)
  end

  defp normalize_string(nil), do: nil

  defp normalize_string(value) when is_binary(value) do
    case String.trim(value) do
      "" -> nil
      trimmed -> trimmed
    end
  end

  defp normalize_string(value), do: value
end

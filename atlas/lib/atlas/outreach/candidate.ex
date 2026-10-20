defmodule Atlas.Outreach.Candidate do
  use Atlas.Schema

  import Ecto.Changeset

  alias Atlas.Accounts.Contact

  @statuses ~w(pending enrolled rejected)

  @derive {
    Flop.Schema,
    filterable: [:status, :search_segment, :source],
    sortable: [:discovered_at, :full_name, :title],
    default_limit: 25,
    max_limit: 100
  }

  schema "outreach_candidates" do
    field :source, :string, default: "apollo"
    field :source_id, :string
    field :search_segment, :string
    field :search_version, :integer, default: 1
    field :status, :string, default: "pending"
    field :full_name, :string
    field :title, :string
    field :organization_name, :string
    field :organization_source_id, :string
    field :organization_domain, :string
    field :linkedin_url, :string
    field :email, :string
    field :rejection_reason, :string
    field :search_rank, :integer
    field :metadata, :map, default: %{}
    field :discovered_at, :utc_datetime
    field :reviewed_at, :utc_datetime
    field :slack_notification_requested_at, :utc_datetime
    field :slack_notification_posted_at, :utc_datetime
    field :slack_notification_channel_id, :string
    field :slack_notification_thread_ts, :string

    belongs_to :contact, Contact

    timestamps()
  end

  def statuses, do: @statuses

  def changeset(candidate, attrs) do
    candidate
    |> cast(attrs, [
      :source,
      :source_id,
      :search_segment,
      :search_version,
      :status,
      :full_name,
      :title,
      :organization_name,
      :organization_source_id,
      :organization_domain,
      :linkedin_url,
      :email,
      :rejection_reason,
      :search_rank,
      :metadata,
      :discovered_at,
      :reviewed_at,
      :contact_id
    ])
    |> normalize_strings([
      :source,
      :source_id,
      :search_segment,
      :full_name,
      :title,
      :organization_name,
      :organization_source_id,
      :organization_domain,
      :linkedin_url,
      :email,
      :rejection_reason
    ])
    |> normalize_email()
    |> validate_required([
      :source,
      :source_id,
      :search_segment,
      :search_version,
      :status,
      :discovered_at
    ])
    |> validate_inclusion(:status, @statuses)
    |> validate_number(:search_version, greater_than: 0)
    |> validate_number(:search_rank, greater_than: 0)
    |> unique_constraint([:source, :source_id])
    |> foreign_key_constraint(:contact_id)
  end

  def review_changeset(candidate, attrs) do
    candidate
    |> cast(attrs, [:status, :rejection_reason, :reviewed_at, :contact_id])
    |> normalize_strings([:rejection_reason])
    |> validate_inclusion(:status, @statuses)
    |> foreign_key_constraint(:contact_id)
  end

  def notification_changeset(candidate, attrs) do
    candidate
    |> change(
      Map.take(attrs, [:slack_notification_posted_at, :slack_notification_channel_id, :slack_notification_thread_ts])
    )
    |> normalize_strings([:slack_notification_channel_id, :slack_notification_thread_ts])
    |> validate_required([
      :slack_notification_posted_at,
      :slack_notification_channel_id,
      :slack_notification_thread_ts
    ])
  end

  defp normalize_strings(changeset, fields) do
    Enum.reduce(fields, changeset, fn field, changeset ->
      update_change(changeset, field, fn
        nil -> nil
        value -> value |> to_string() |> String.trim() |> empty_to_nil()
      end)
    end)
  end

  defp normalize_email(changeset) do
    update_change(changeset, :email, fn
      nil -> nil
      email -> String.downcase(email)
    end)
  end

  defp empty_to_nil(""), do: nil
  defp empty_to_nil(value), do: value
end

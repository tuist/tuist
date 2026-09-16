defmodule Atlas.Accounts.Contact do
  use Atlas.Schema

  import Ecto.Changeset

  alias Atlas.Accounts.Account
  alias Atlas.Accounts.Event
  alias Atlas.Outreach.MessageAttempt
  alias Atlas.Outreach.Recommendation

  @outreach_statuses ~w(not_contacted connection_requested connected conversation_started replied interested not_interested)

  @derive {
    Flop.Schema,
    filterable: [:outreach_status, :account_id, :source],
    sortable: [:outreach_enrolled_at, :last_outreach_at, :full_name],
    default_limit: 25,
    max_limit: 100
  }

  schema "account_contacts" do
    field :full_name, :string
    field :email, :string
    field :title, :string
    field :notes, :string
    field :source, :string, default: "manual"
    field :source_id, :string
    field :linkedin_url, :string
    field :outreach_status, :string, default: "not_contacted"
    field :outreach_enrolled_at, :utc_datetime
    field :last_outreach_at, :utc_datetime
    field :outreach_recommendations_checked_at, :utc_datetime
    field :metadata, :map, default: %{}

    belongs_to :account, Account
    has_many :events, Event
    has_many :outreach_recommendations, Recommendation
    has_many :outreach_message_attempts, MessageAttempt

    timestamps()
  end

  def outreach_statuses, do: @outreach_statuses

  def changeset(contact, attrs) do
    contact
    |> cast(attrs, [:full_name, :email, :title, :notes, :linkedin_url, :account_id])
    |> validate_changeset()
  end

  def outreach_changeset(contact, attrs) do
    contact
    |> cast(attrs, [
      :full_name,
      :email,
      :title,
      :notes,
      :linkedin_url,
      :account_id,
      :source,
      :source_id,
      :outreach_status,
      :outreach_enrolled_at,
      :last_outreach_at,
      :metadata
    ])
    |> validate_changeset()
  end

  defp validate_changeset(changeset) do
    changeset
    |> validate_required([:full_name, :source, :outreach_status, :account_id])
    |> update_change(:full_name, &String.trim/1)
    |> update_change(:email, &normalize_optional_email/1)
    |> normalize_optional_fields()
    |> validate_contact_identity()
    |> validate_inclusion(:outreach_status, @outreach_statuses)
    |> unique_constraint(:email, name: :account_contacts_account_id_email_index)
    |> unique_constraint(:linkedin_url, name: :account_contacts_account_id_linkedin_url_index)
    |> unique_constraint(:source_id, name: :account_contacts_account_id_source_source_id_index)
    |> check_constraint(:email, name: :account_contacts_email_or_linkedin_url)
  end

  def edit_changeset(contact, attrs) do
    contact
    |> cast(attrs, [:full_name, :email, :title, :notes, :linkedin_url])
    |> validate_required([:full_name])
    |> update_change(:full_name, &String.trim/1)
    |> update_change(:email, &normalize_optional_email/1)
    |> normalize_optional_fields()
    |> validate_contact_identity()
    |> unique_constraint(:email, name: :account_contacts_account_id_email_index)
    |> unique_constraint(:linkedin_url, name: :account_contacts_account_id_linkedin_url_index)
    |> check_constraint(:email, name: :account_contacts_email_or_linkedin_url)
  end

  def outreach_recommendations_checked_changeset(contact, attrs) do
    contact
    |> change(Map.take(attrs, [:outreach_recommendations_checked_at]))
    |> validate_required([:outreach_recommendations_checked_at])
  end

  defp normalize_optional_fields(changeset) do
    Enum.reduce([:title, :notes, :source_id, :linkedin_url], changeset, &normalize_optional_field/2)
  end

  defp normalize_optional_field(field, changeset) do
    update_change(changeset, field, fn value ->
      case value do
        nil ->
          nil

        value ->
          value
          |> String.trim()
          |> case do
            "" -> nil
            normalized -> normalized
          end
      end
    end)
  end

  defp normalize_optional_email(nil), do: nil

  defp normalize_optional_email(value) do
    value
    |> String.trim()
    |> String.downcase()
    |> case do
      "" -> nil
      normalized -> normalized
    end
  end

  defp validate_contact_identity(changeset) do
    if get_field(changeset, :email) || get_field(changeset, :linkedin_url) do
      changeset
    else
      add_error(changeset, :email, "or LinkedIn profile is required")
    end
  end
end

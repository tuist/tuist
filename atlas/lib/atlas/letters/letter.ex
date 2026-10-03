defmodule Atlas.Letters.Letter do
  @moduledoc false

  use Atlas.Schema

  import Ecto.Changeset

  alias Atlas.Accounts.Account
  alias Atlas.Documents.Document
  alias Atlas.Users.User

  @kinds ["tax_certificate_request", "uploaded_letter"]
  @statuses [
    "awaiting_signature",
    "collecting_delivery_details",
    "awaiting_delivery_confirmation",
    "queued",
    "sending",
    "sent",
    "delivered",
    "undeliverable",
    "failed"
  ]
  @recipient_fields [
    :recipient_name,
    :recipient_street,
    :recipient_postal_code,
    :recipient_city,
    :recipient_country,
    :recipient_reference
  ]
  @template_fields [:foundation_date, :legal_form, :submission_to, :certificate_purpose, :signing_location]
  @required_tax_certificate_fields (@recipient_fields -- [:recipient_reference]) ++
                                     [:foundation_date, :legal_form, :submission_to, :certificate_purpose]
  @required_tax_certificate_letter_fields [
    :account_id,
    :created_by_id,
    :kind,
    :status,
    :sender_name,
    :sender_street,
    :sender_postal_code,
    :sender_city,
    :sender_country,
    :subject,
    :body
  ]
  @required_uploaded_letter_fields [:created_by_id, :kind, :status, :subject, :body]

  @derive {
    Flop.Schema,
    filterable: [:account_id, :status, :kind],
    sortable: [:inserted_at, :confirmed_at, :sent_at, :delivered_at],
    default_limit: 25,
    max_limit: 100
  }

  schema "letters" do
    field :kind, :string
    field :status, :string, default: "awaiting_signature"
    field :recipient_name, :string
    field :recipient_street, :string
    field :recipient_postal_code, :string
    field :recipient_city, :string
    field :recipient_country, :string, default: "DE"
    field :recipient_reference, :string
    field :sender_name, :string
    field :sender_street, :string
    field :sender_postal_code, :string
    field :sender_city, :string
    field :sender_country, :string, default: "DE"
    field :signatory_name, :string
    field :signatory_title, :string
    field :tax_id, :string
    field :vat_id, :string
    field :subject, :string
    field :body, :string
    field :template_data, :map, default: %{}
    field :foundation_date, :date, virtual: true
    field :legal_form, :string, virtual: true
    field :submission_to, :string, virtual: true
    field :certificate_purpose, :string, virtual: true
    field :signing_location, :string, virtual: true
    field :pingen_letter_id, :string
    field :pingen_tracking_number, :string
    field :pingen_status, :string
    field :pingen_events, :map, default: %{"items" => []}
    field :delivery_details, :map
    field :last_error, :string
    field :confirmed_at, :utc_datetime
    field :sent_at, :utc_datetime
    field :delivered_at, :utc_datetime
    field :undeliverable_at, :utc_datetime
    field :last_checked_at, :utc_datetime
    field :signed_uploaded_at, :utc_datetime
    field :delivery_prepared_at, :utc_datetime

    belongs_to :account, Account
    belongs_to :document, Document
    belongs_to :signed_document, Document
    belongs_to :created_by, User
    belongs_to :confirmed_by, User
    belongs_to :signed_uploaded_by, User

    timestamps()
  end

  def kinds, do: @kinds
  def statuses, do: @statuses

  def tax_certificate_request_changeset(letter, attrs) do
    letter
    |> cast(attrs, @recipient_fields ++ @template_fields)
    |> validate_required(@required_tax_certificate_fields)
    |> normalize_recipient_strings()
    |> normalize_template_strings()
    |> validate_inclusion(:recipient_country, ["DE"])
  end

  def changeset(letter, attrs) do
    letter
    |> cast(attrs, [
      :account_id,
      :document_id,
      :signed_document_id,
      :created_by_id,
      :confirmed_by_id,
      :signed_uploaded_by_id,
      :kind,
      :status,
      :recipient_name,
      :recipient_street,
      :recipient_postal_code,
      :recipient_city,
      :recipient_country,
      :recipient_reference,
      :sender_name,
      :sender_street,
      :sender_postal_code,
      :sender_city,
      :sender_country,
      :signatory_name,
      :signatory_title,
      :tax_id,
      :vat_id,
      :subject,
      :body,
      :template_data,
      :pingen_letter_id,
      :pingen_tracking_number,
      :pingen_status,
      :pingen_events,
      :delivery_details,
      :last_error,
      :confirmed_at,
      :sent_at,
      :delivered_at,
      :undeliverable_at,
      :last_checked_at,
      :signed_uploaded_at,
      :delivery_prepared_at
    ])
    |> then(&validate_required(&1, required_fields_for_kind(&1)))
    |> validate_recipient_for_kind()
    |> normalize_recipient_strings()
    |> normalize_sender_strings()
    |> validate_inclusion(:kind, @kinds)
    |> validate_inclusion(:status, @statuses)
    |> validate_inclusion(:recipient_country, ["DE"])
    |> validate_inclusion(:sender_country, ["DE"])
    |> foreign_key_constraint(:account_id)
    |> foreign_key_constraint(:document_id)
    |> foreign_key_constraint(:signed_document_id)
    |> foreign_key_constraint(:created_by_id)
    |> foreign_key_constraint(:confirmed_by_id)
    |> foreign_key_constraint(:signed_uploaded_by_id)
    |> unique_constraint(:pingen_letter_id)
  end

  defp normalize_recipient_strings(changeset) do
    changeset
    |> normalize_strings(@recipient_fields)
    |> update_change(:recipient_country, &String.upcase/1)
  end

  defp validate_recipient_for_kind(changeset) do
    if get_field(changeset, :kind) == "tax_certificate_request" do
      validate_required(changeset, @recipient_fields -- [:recipient_reference])
    else
      changeset
    end
  end

  defp required_fields_for_kind(changeset) do
    case get_field(changeset, :kind) do
      "uploaded_letter" -> @required_uploaded_letter_fields
      _kind -> @required_tax_certificate_letter_fields
    end
  end

  defp normalize_sender_strings(changeset) do
    changeset
    |> normalize_strings([
      :sender_name,
      :sender_street,
      :sender_postal_code,
      :sender_city,
      :sender_country,
      :signatory_name,
      :signatory_title,
      :tax_id,
      :vat_id,
      :subject,
      :body,
      :pingen_letter_id,
      :pingen_tracking_number,
      :pingen_status,
      :last_error
    ])
    |> update_change(:sender_country, &String.upcase/1)
  end

  defp normalize_template_strings(changeset) do
    normalize_strings(changeset, [:legal_form, :submission_to, :certificate_purpose, :signing_location])
  end

  defp normalize_strings(changeset, fields) do
    Enum.reduce(fields, changeset, fn field, changeset ->
      update_change(changeset, field, &normalize_string/1)
    end)
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

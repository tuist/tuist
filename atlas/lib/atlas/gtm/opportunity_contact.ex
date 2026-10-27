defmodule Atlas.GTM.OpportunityContact do
  use Atlas.Schema

  import Ecto.Changeset

  alias Atlas.GTM.Opportunity

  schema "gtm_opportunity_contacts" do
    field :source, :string, default: "apollo"
    field :full_name, :string
    field :title, :string
    field :organization_name, :string
    field :linkedin_url, :string
    field :email, :string
    field :confidence, :integer, default: 0
    field :metadata, :map, default: %{}

    belongs_to :opportunity, Opportunity

    timestamps()
  end

  def changeset(contact, attrs) do
    contact
    |> cast(attrs, [
      :source,
      :full_name,
      :title,
      :organization_name,
      :linkedin_url,
      :email,
      :confidence,
      :metadata
    ])
    |> normalize_string_fields([:source, :full_name, :title, :organization_name, :linkedin_url, :email])
    |> normalize_email()
    |> validate_required([:source, :title, :confidence, :opportunity_id])
    |> validate_number(:confidence, greater_than_or_equal_to: 0, less_than_or_equal_to: 100)
    |> unique_constraint([:opportunity_id, :linkedin_url],
      name: :gtm_opportunity_contacts_opportunity_id_linkedin_url_index
    )
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

  defp normalize_email(changeset) do
    update_change(changeset, :email, fn
      nil -> nil
      email -> String.downcase(email)
    end)
  end
end

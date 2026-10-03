defmodule Atlas.Accounts.Account.Billing do
  use Ecto.Schema

  import Ecto.Changeset

  @fields [:tax_id, :vat_id, :sold_to, :bill_to, :email, :phone]

  @primary_key false

  embedded_schema do
    field :tax_id, :string
    field :vat_id, :string
    field :sold_to, :string
    field :bill_to, :string
    field :email, :string
    field :phone, :string
  end

  def changeset(billing, attrs) do
    billing
    |> cast(attrs, @fields)
    |> normalize_strings()
    |> update_change(:email, &maybe_downcase/1)
  end

  def empty?(nil), do: true

  def empty?(%__MODULE__{} = billing) do
    Enum.all?(@fields, fn field -> blank?(Map.get(billing, field)) end)
  end

  defp normalize_strings(changeset) do
    Enum.reduce(@fields, changeset, fn field, acc ->
      update_change(acc, field, &normalize/1)
    end)
  end

  defp normalize(nil), do: nil

  defp normalize(value) when is_binary(value) do
    case String.trim(value) do
      "" -> nil
      trimmed -> trimmed
    end
  end

  defp maybe_downcase(nil), do: nil
  defp maybe_downcase(value) when is_binary(value), do: String.downcase(value)

  defp blank?(nil), do: true
  defp blank?(""), do: true
  defp blank?(value) when is_binary(value), do: String.trim(value) == ""
  defp blank?(_), do: false
end

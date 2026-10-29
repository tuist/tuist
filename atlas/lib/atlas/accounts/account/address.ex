defmodule Atlas.Accounts.Account.Address do
  use Ecto.Schema

  import Ecto.Changeset

  @primary_key false

  embedded_schema do
    field :street, :string
    field :city, :string
    field :zip, :string
    field :country, :string
  end

  def changeset(address, attrs) do
    address
    |> cast(attrs, [:street, :city, :zip, :country])
    |> normalize_strings()
  end

  def empty?(nil), do: true

  def empty?(%__MODULE__{street: street, city: city, zip: zip, country: country}) do
    Enum.all?([street, city, zip, country], &blank?/1)
  end

  defp normalize_strings(changeset) do
    Enum.reduce([:street, :city, :zip, :country], changeset, fn field, acc ->
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

  defp blank?(nil), do: true
  defp blank?(""), do: true
  defp blank?(value) when is_binary(value), do: String.trim(value) == ""
  defp blank?(_), do: false
end

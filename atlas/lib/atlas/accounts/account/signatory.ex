defmodule Atlas.Accounts.Account.Signatory do
  use Ecto.Schema

  import Ecto.Changeset

  @primary_key false

  embedded_schema do
    field :name, :string
    field :title, :string
  end

  def changeset(signatory, attrs) do
    signatory
    |> cast(attrs, [:name, :title])
    |> normalize_strings()
  end

  def empty?(nil), do: true

  def empty?(%__MODULE__{name: name, title: title}) do
    blank?(name) and blank?(title)
  end

  defp normalize_strings(changeset) do
    Enum.reduce([:name, :title], changeset, fn field, acc ->
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

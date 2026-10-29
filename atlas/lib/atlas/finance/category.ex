defmodule Atlas.Finance.Category do
  use Atlas.Schema

  import Ecto.Changeset

  alias Atlas.Finance.Transaction

  @max_name_words 5
  @display_name_overrides %{
    "subscription" => "Software Subscription",
    "subscriptions" => "Software Subscription",
    "software subscription" => "Software Subscription",
    "software subscriptions" => "Software Subscription",
    "saas" => "Software Subscription",
    "baremetal" => "Bare Metal",
    "bare metal" => "Bare Metal"
  }
  @display_acronyms %{
    "ai" => "AI",
    "api" => "API",
    "aws" => "AWS",
    "gcp" => "GCP",
    "saas" => "SaaS",
    "sso" => "SSO",
    "vat" => "VAT"
  }

  schema "finance_categories" do
    field :name, :string
    field :slug, :string
    field :description, :string
    field :direction, :string
    field :created_by_agent, :string
    field :metadata, :map, default: %{}

    has_many :transactions, Transaction, foreign_key: :finance_category_id

    timestamps()
  end

  def changeset(category, attrs) do
    category
    |> cast(attrs, [:name, :slug, :description, :direction, :created_by_agent, :metadata])
    |> update_change(:name, &normalize_name/1)
    |> put_slug()
    |> update_change(:description, &normalize_optional_string/1)
    |> update_change(:direction, &normalize_optional_string/1)
    |> update_change(:created_by_agent, &normalize_optional_string/1)
    |> validate_required([:name, :slug])
    |> validate_length(:name, min: 3, max: 80)
    |> validate_length(:description, max: 500)
    |> validate_direction()
    |> validate_broad_name()
    |> unique_constraint(:slug)
  end

  def slugify(name) when is_binary(name) do
    name
    |> String.downcase()
    |> String.replace(~r/[^a-z0-9]+/u, "-")
    |> String.trim("-")
  end

  def slugify(_name), do: nil

  def display_name(nil), do: nil

  def display_name(name) when is_binary(name) do
    key = display_key(name)

    cond do
      key == "" -> nil
      display_name = @display_name_overrides[key] -> display_name
      display_normalization_needed?(name) -> titleize_display_name(name)
      true -> String.trim(name)
    end
  end

  def display_name(name), do: name

  defp put_slug(changeset) do
    case get_field(changeset, :slug) do
      value when is_binary(value) and value != "" ->
        update_change(changeset, :slug, &slugify/1)

      _value ->
        put_change(changeset, :slug, slugify(get_field(changeset, :name)))
    end
  end

  defp validate_broad_name(changeset) do
    name = get_field(changeset, :name)

    cond do
      !is_binary(name) ->
        changeset

      Regex.match?(~r/\d/, name) ->
        add_error(changeset, :name, "must be reusable and must not include numbers")

      name |> String.split(~r/\s+/, trim: true) |> length() > @max_name_words ->
        add_error(changeset, :name, "must be broad enough to reuse across transactions")

      true ->
        changeset
    end
  end

  defp validate_direction(changeset) do
    case get_field(changeset, :direction) do
      nil -> changeset
      direction when direction in ["credit", "debit"] -> changeset
      _direction -> add_error(changeset, :direction, "must be credit or debit")
    end
  end

  defp normalize_name(nil), do: nil

  defp normalize_name(value) when is_binary(value) do
    value
    |> String.trim()
    |> String.replace(~r/\s+/, " ")
  end

  defp normalize_name(value), do: value

  defp normalize_optional_string(nil), do: nil

  defp normalize_optional_string(value) when is_binary(value) do
    case String.trim(value) do
      "" -> nil
      trimmed -> trimmed
    end
  end

  defp normalize_optional_string(value), do: value

  defp display_key(name) do
    name
    |> String.downcase()
    |> String.replace(~r/[^a-z0-9]+/u, " ")
    |> String.replace(~r/\s+/, " ")
    |> String.trim()
  end

  defp display_normalization_needed?(name) do
    trimmed = String.trim(name)

    String.contains?(trimmed, ["_", "-"]) or trimmed == String.downcase(trimmed) or trimmed == String.upcase(trimmed)
  end

  defp titleize_display_name(name) do
    name
    |> String.replace(~r/[_-]+/u, " ")
    |> String.replace(~r/\s+/, " ")
    |> String.trim()
    |> String.split(" ", trim: true)
    |> Enum.map_join(" ", &display_word/1)
  end

  defp display_word(word) do
    key = String.downcase(word)
    Map.get(@display_acronyms, key, String.capitalize(key))
  end
end

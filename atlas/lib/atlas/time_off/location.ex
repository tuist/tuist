defmodule Atlas.TimeOff.Location do
  use Atlas.Schema

  import Ecto.Changeset

  schema "time_off_locations" do
    field :name, :string
    field :country_code, :string
    field :subdivision_code, :string
    field :synced_years, {:array, :integer}, default: []

    timestamps(type: :utc_datetime)
  end

  def changeset(location, attrs) do
    location
    |> cast(attrs, [:name, :country_code, :subdivision_code])
    |> update_change(:country_code, &String.upcase/1)
    |> update_change(:subdivision_code, &String.upcase/1)
    |> validate_required([:name, :country_code])
    |> validate_length(:name, max: 100)
    |> validate_format(:country_code, ~r/^[A-Z]{2}$/)
    |> validate_format(:subdivision_code, ~r/^[A-Z]{2}-[A-Z0-9]{1,3}$/)
    |> validate_subdivision()
    |> unique_constraint(:name)
  end

  defp validate_subdivision(changeset) do
    country = get_field(changeset, :country_code)
    subdivision = get_field(changeset, :subdivision_code)

    if country && subdivision && !String.starts_with?(subdivision, country <> "-") do
      add_error(changeset, :subdivision_code, "must belong to the selected country")
    else
      changeset
    end
  end
end

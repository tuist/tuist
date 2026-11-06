defmodule Atlas.TimeOff.Holiday do
  use Atlas.Schema

  import Ecto.Changeset

  alias Atlas.TimeOff.Location

  schema "time_off_holidays" do
    belongs_to :location, Location
    field :name, :string
    field :date, :date
    field :source, :string, default: "manual"

    timestamps(type: :utc_datetime)
  end

  def changeset(holiday, attrs) do
    holiday
    |> cast(attrs, [:name, :date])
    |> validate_required([:name, :date, :location_id, :source])
    |> validate_length(:name, max: 150)
    |> validate_change(:date, fn :date, date ->
      if date.year in 2000..2100, do: [], else: [date: "must be between 2000 and 2100"]
    end)
    |> foreign_key_constraint(:location_id)
    |> unique_constraint([:location_id, :date, :name, :source])
  end
end

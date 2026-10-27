defmodule Atlas.TimeOff.Booking do
  use Atlas.Schema

  import Ecto.Changeset

  alias Atlas.TimeOff.Location
  alias Atlas.Users.User

  schema "time_off_bookings" do
    belongs_to :user, User
    belongs_to :location, Location
    field :starts_on, :date
    field :ends_on, :date
    field :status, :string, default: "pending"
    field :cancelled_at, :utc_datetime
    belongs_to :reviewed_by, User
    field :reviewed_at, :utc_datetime

    timestamps(type: :utc_datetime)
  end

  def changeset(booking, attrs) do
    booking
    |> cast(attrs, [:starts_on, :ends_on])
    |> validate_required([:starts_on, :ends_on])
    |> validate_dates()
    |> check_constraint(:ends_on, name: :time_off_bookings_date_order)
    |> foreign_key_constraint(:user_id)
    |> foreign_key_constraint(:location_id)
  end

  defp validate_dates(changeset) do
    with %Date{} = first <- get_field(changeset, :starts_on),
         %Date{} = last <- get_field(changeset, :ends_on) do
      cond do
        Date.before?(last, first) ->
          add_error(changeset, :ends_on, "must be on or after the start date")

        Date.diff(last, first) > 365 ->
          add_error(changeset, :ends_on, "must be within one year of the start date")

        first.year < 2000 or last.year > 2100 ->
          add_error(changeset, :ends_on, "must be between 2000 and 2100")

        true ->
          changeset
      end
    else
      _ -> changeset
    end
  end
end

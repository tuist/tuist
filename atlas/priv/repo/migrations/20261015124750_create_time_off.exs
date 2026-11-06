defmodule Atlas.Repo.Migrations.CreateTimeOff do
  use Ecto.Migration

  def change do
    create table(:time_off_locations, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :name, :string, null: false
      add :country_code, :string, null: false
      add :subdivision_code, :string
      add :synced_years, {:array, :integer}, null: false, default: []
      timestamps(type: :timestamptz)
    end

    create unique_index(:time_off_locations, [:name])

    alter table(:users) do
      add :time_off_location_id,
          references(:time_off_locations, type: :binary_id, on_delete: :restrict)
    end

    create index(:users, [:time_off_location_id])

    create table(:time_off_holidays, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :location_id, references(:time_off_locations, type: :binary_id, on_delete: :restrict),
        null: false

      add :name, :string, null: false
      add :date, :date, null: false
      add :source, :string, null: false, default: "manual"
      timestamps(type: :timestamptz)
    end

    create unique_index(:time_off_holidays, [:location_id, :date, :name, :source])
    create index(:time_off_holidays, [:date])

    create table(:time_off_bookings, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :user_id, references(:users, type: :binary_id, on_delete: :delete_all), null: false

      add :location_id, references(:time_off_locations, type: :binary_id, on_delete: :restrict),
        null: false

      add :starts_on, :date, null: false
      add :ends_on, :date, null: false
      add :status, :string, null: false, default: "booked"
      add :cancelled_at, :timestamptz
      timestamps(type: :timestamptz)
    end

    create index(:time_off_bookings, [:user_id])
    create index(:time_off_bookings, [:location_id])
    create index(:time_off_bookings, [:starts_on, :ends_on], where: "status = 'booked'")

    create constraint(:time_off_bookings, :time_off_bookings_date_order,
             check: "ends_on >= starts_on"
           )

    create constraint(:time_off_bookings, :time_off_bookings_status,
             check: "status IN ('booked', 'cancelled')"
           )
  end
end

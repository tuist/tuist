defmodule Credo.Checks.MigrationsTimestamptzTest do
  use Credo.Test.Case

  alias Credo.Checks.TimestampsType

  describe "when allowed type is timestamptz" do
    test "when timestamptz is specified, it should not raise a violation" do
      """
      defmodule Tuist.Repo.Migrations.AddPreviewsTable do
      use Ecto.Migration

        def change do
          create table(:previews, primary_key: false) do
            add :id, :uuid, primary_key: true, null: false
            add :project_id, references(:projects, on_delete: :delete_all), required: true
            timestamps(type: :timestamptz)
          end
        end
      end
      """
      |> to_source_file()
      |> run_check(TimestampsType, allowed_type: :timestamptz)
      |> refute_issues()
    end

    test "when timestamps has a type different than timestamptz, it should report a violation" do
      """
      defmodule Tuist.Repo.Migrations.AddPreviewsTable do
      use Ecto.Migration

        def change do
          create table(:previews, primary_key: false) do
            add :id, :uuid, primary_key: true, null: false
            add :project_id, references(:projects, on_delete: :delete_all), required: true
            timestamps(type: :naive_datetime)
          end
        end
      end
      """
      |> to_source_file()
      |> run_check(TimestampsType, allowed_type: :timestamptz)
      |> assert_issue()
    end

    test "when timestamps has only updated_at, it should report a violation" do
      """
      defmodule Tuist.Repo.Migrations.AddPreviewsTable do
      use Ecto.Migration

        def change do
          create table(:previews, primary_key: false) do
            add :id, :uuid, primary_key: true, null: false
            add :project_id, references(:projects, on_delete: :delete_all), required: true
            timestamps(updated_at: false)
          end
        end
      end
      """
      |> to_source_file()
      |> run_check(TimestampsType, allowed_type: :timestamptz)
      |> assert_issue()
    end

    test "when timestamps has no opts, it should report a violation" do
      """
      defmodule Tuist.Repo.Migrations.AddPreviewsTable do
      use Ecto.Migration

        def change do
          create table(:previews, primary_key: false) do
            add :id, :uuid, primary_key: true, null: false
            add :project_id, references(:projects, on_delete: :delete_all), required: true
            timestamps()
          end
        end
      end
      """
      |> to_source_file()
      |> run_check(TimestampsType, allowed_type: :timestamptz)
      |> assert_issue()
    end
  end

  describe "when allowed type is utc_datetime" do
    test "when timestamps in a schema has no opts, it should report a violation" do
      """
      defmodule Tuist.Accounts.DeviceCode do
        use Ecto.Schema
        import Ecto.Changeset
        alias Tuist.Accounts.User

        schema "device_codes" do
          field :code, :string
          field :authenticated, :boolean, default: false
          belongs_to :user, User
          timestamps()
        end
      end
      """
      |> to_source_file()
      |> run_check(TimestampsType, allowed_type: :utc_datetime)
      |> assert_issue()
    end

    test "when timestamps in a schema has a utc_datetime, it should not report a violation" do
      """
      defmodule Tuist.Accounts.DeviceCode do
        use Ecto.Schema
        import Ecto.Changeset
        alias Tuist.Accounts.User

        schema "device_codes" do
          field :code, :string
          field :authenticated, :boolean, default: false
          belongs_to :user, User
          timestamps(type: :utc_datetime)
        end
      end
      """
      |> to_source_file()
      |> run_check(TimestampsType, allowed_type: :utc_datetime)
      |> refute_issues()
    end
  end
end

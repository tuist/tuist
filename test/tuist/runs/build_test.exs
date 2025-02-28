defmodule Tuist.Runs.BuildTest do
  use TuistTestSupport.Cases.DataCase, async: true

  alias Tuist.Runs.Build

  describe "create_changeset/2" do
    @valid_attrs %{
      id: "B12673DA-1345-4077-BB30-D7576FEACE09",
      duration: 120,
      macos_version: "11.2.3",
      xcode_version: "12.4",
      is_ci: true,
      model_identifier: "Mac15,6",
      scheme: "App",
      project_id: 1,
      account_id: 1,
      inserted_at: ~U[2023-10-01 12:00:00Z]
    }

    test "is valid when contains all necessary attributes" do
      changeset = Build.create_changeset(%Build{}, @valid_attrs)
      assert changeset.valid?
    end

    test "ensures id is present" do
      changeset = Build.create_changeset(%Build{}, Map.drop(@valid_attrs, [:id]))
      assert "can't be blank" in errors_on(changeset).id
    end

    test "ensures duration is present" do
      changeset = Build.create_changeset(%Build{}, Map.drop(@valid_attrs, [:duration]))
      assert "can't be blank" in errors_on(changeset).duration
    end

    test "ensures is_ci is present" do
      changeset = Build.create_changeset(%Build{}, Map.drop(@valid_attrs, [:is_ci]))
      assert "can't be blank" in errors_on(changeset).is_ci
    end

    test "ensures project_id is present" do
      changeset = Build.create_changeset(%Build{}, Map.drop(@valid_attrs, [:project_id]))
      assert "can't be blank" in errors_on(changeset).project_id
    end

    test "ensures account_id is present" do
      changeset = Build.create_changeset(%Build{}, Map.drop(@valid_attrs, [:account_id]))
      assert "can't be blank" in errors_on(changeset).account_id
    end
  end
end

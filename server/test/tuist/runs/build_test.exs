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
      status: :success,
      inserted_at: ~U[2023-10-01 12:00:00Z]
    }

    test "is valid when contains all necessary attributes" do
      changeset = Build.create_changeset(%Build{}, @valid_attrs)
      assert changeset.valid?
    end

    test "ensures id is present" do
      changeset = Build.create_changeset(%Build{}, Map.delete(@valid_attrs, :id))
      assert "can't be blank" in errors_on(changeset).id
    end

    test "ensures id is a valid UUID" do
      changeset = Build.create_changeset(%Build{}, Map.put(@valid_attrs, :id, "invalid"))
      assert "is invalid" in errors_on(changeset).id
    end

    test "ensures duration is present" do
      changeset = Build.create_changeset(%Build{}, Map.delete(@valid_attrs, :duration))
      assert "can't be blank" in errors_on(changeset).duration
    end

    test "ensures is_ci is present" do
      changeset = Build.create_changeset(%Build{}, Map.delete(@valid_attrs, :is_ci))
      assert "can't be blank" in errors_on(changeset).is_ci
    end

    test "ensures project_id is present" do
      changeset = Build.create_changeset(%Build{}, Map.delete(@valid_attrs, :project_id))
      assert "can't be blank" in errors_on(changeset).project_id
    end

    test "ensures account_id is present" do
      changeset = Build.create_changeset(%Build{}, Map.delete(@valid_attrs, :account_id))
      assert "can't be blank" in errors_on(changeset).account_id
    end

    test "ensures status is present" do
      changeset = Build.create_changeset(%Build{}, Map.delete(@valid_attrs, :status))
      assert "can't be blank" in errors_on(changeset).status
    end

    test "ensures status is a valid value" do
      invalid_attrs = Map.put(@valid_attrs, :status, :invalid_status)
      changeset = Build.create_changeset(%Build{}, invalid_attrs)
      assert "is invalid" in errors_on(changeset).status
    end

    test "is valid when status is :failure" do
      attrs = Map.put(@valid_attrs, :status, :failure)
      changeset = Build.create_changeset(%Build{}, attrs)
      assert changeset.valid?
    end

    test "is valid when ci_provider is a valid value" do
      attrs = Map.put(@valid_attrs, :ci_provider, :github)
      changeset = Build.create_changeset(%Build{}, attrs)
      assert changeset.valid?
    end

    test "ensures ci_provider is a valid value" do
      invalid_attrs = Map.put(@valid_attrs, :ci_provider, :invalid_provider)
      changeset = Build.create_changeset(%Build{}, invalid_attrs)
      assert "is invalid" in errors_on(changeset).ci_provider
    end

    test "is valid with optional CI metadata fields" do
      attrs =
        Map.merge(@valid_attrs, %{
          ci_run_id: "run-123",
          ci_project_handle: "org/repo",
          ci_host: "github.com",
          ci_provider: :github
        })

      changeset = Build.create_changeset(%Build{}, attrs)
      assert changeset.valid?
    end

    test "is valid with custom_tags" do
      attrs = Map.put(@valid_attrs, :custom_tags, ["nightly", "release", "staging"])
      changeset = Build.create_changeset(%Build{}, attrs)
      assert changeset.valid?
    end

    test "is valid with custom_values" do
      attrs = Map.put(@valid_attrs, :custom_values, %{"ticket" => "PROJ-1234", "runner" => "macos-14"})
      changeset = Build.create_changeset(%Build{}, attrs)
      assert changeset.valid?
    end

    test "rejects more than 50 custom_tags" do
      tags = Enum.map(1..51, fn i -> "tag#{i}" end)
      attrs = Map.put(@valid_attrs, :custom_tags, tags)
      changeset = Build.create_changeset(%Build{}, attrs)
      assert "cannot have more than 50 tags" in errors_on(changeset).custom_tags
    end

    test "rejects custom_tags longer than 50 characters" do
      long_tag = String.duplicate("a", 51)
      attrs = Map.put(@valid_attrs, :custom_tags, [long_tag])
      changeset = Build.create_changeset(%Build{}, attrs)
      assert "tag exceeds maximum length of 50 characters" in errors_on(changeset).custom_tags
    end

    test "rejects custom_tags with invalid characters" do
      attrs = Map.put(@valid_attrs, :custom_tags, ["invalid tag!"])
      changeset = Build.create_changeset(%Build{}, attrs)

      assert "tag contains invalid characters (only alphanumeric, hyphens, and underscores allowed)" in errors_on(
               changeset
             ).custom_tags
    end

    test "accepts custom_tags with alphanumeric, hyphens, and underscores" do
      attrs = Map.put(@valid_attrs, :custom_tags, ["valid-tag", "valid_tag", "validTag123"])
      changeset = Build.create_changeset(%Build{}, attrs)
      assert changeset.valid?
    end

    test "rejects more than 20 custom_values" do
      values = Map.new(1..21, fn i -> {"key#{i}", "value#{i}"} end)
      attrs = Map.put(@valid_attrs, :custom_values, values)
      changeset = Build.create_changeset(%Build{}, attrs)
      assert "cannot have more than 20 key-value pairs" in errors_on(changeset).custom_values
    end

    test "rejects custom_values with keys longer than 50 characters" do
      long_key = String.duplicate("a", 51)
      attrs = Map.put(@valid_attrs, :custom_values, %{long_key => "value"})
      changeset = Build.create_changeset(%Build{}, attrs)
      errors = errors_on(changeset).custom_values
      assert Enum.any?(errors, &String.contains?(&1, "exceeds maximum length of 50 characters"))
    end

    test "rejects custom_values with values longer than 500 characters" do
      long_value = String.duplicate("a", 501)
      attrs = Map.put(@valid_attrs, :custom_values, %{"key" => long_value})
      changeset = Build.create_changeset(%Build{}, attrs)
      errors = errors_on(changeset).custom_values
      assert Enum.any?(errors, &String.contains?(&1, "exceeds maximum length of 500 characters"))
    end
  end
end

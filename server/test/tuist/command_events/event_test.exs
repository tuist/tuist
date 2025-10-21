defmodule Tuist.CommandEvents.EventTest do
  use TuistTestSupport.Cases.DataCase

  alias Tuist.CommandEvents.Event

  describe "changeset/1" do
    test "generates ID when not provided" do
      attrs = %{name: "test"}
      result = Event.changeset(attrs)

      assert Map.has_key?(result, :id)
      assert is_binary(result.id)
      assert String.length(result.id) == 36
    end

    test "preserves existing ID when provided" do
      uuid = "01234567-89ab-cdef-0123-456789abcdef"
      attrs = %{id: uuid, name: "test"}
      result = Event.changeset(attrs)

      assert result.id == uuid
    end

    test "transforms status :success to 0" do
      attrs = %{status: :success}
      result = Event.changeset(attrs)

      assert result.status == 0
    end

    test "transforms status :failure to 1" do
      attrs = %{status: :failure}
      result = Event.changeset(attrs)

      assert result.status == 1
    end

    test "preserves numeric status values" do
      attrs = %{status: 0}
      result = Event.changeset(attrs)

      assert result.status == 0

      attrs = %{status: 1}
      result = Event.changeset(attrs)

      assert result.status == 1
    end

    test "preserves other status values unchanged" do
      attrs = %{status: "unknown"}
      result = Event.changeset(attrs)

      assert result.status == "unknown"
    end

    test "does not modify attrs without status field" do
      attrs = %{name: "test"}
      result = Event.changeset(attrs)

      refute Map.has_key?(result, :status)
    end

    test "transforms command_arguments list to string" do
      attrs = %{command_arguments: ["tuist", "generate", "--verbose"]}
      result = Event.changeset(attrs)

      assert result.command_arguments == "tuist generate --verbose"
    end

    test "preserves command_arguments when already a string" do
      attrs = %{command_arguments: "tuist generate --verbose"}
      result = Event.changeset(attrs)

      assert result.command_arguments == "tuist generate --verbose"
    end

    test "defaults command_arguments to empty string when nil" do
      attrs = %{command_arguments: nil}
      result = Event.changeset(attrs)

      assert result.command_arguments == ""
    end

    test "defaults command_arguments to empty string when not provided" do
      attrs = %{name: "test"}
      result = Event.changeset(attrs)

      assert result.command_arguments == ""
    end

    test "defaults command_arguments to empty string for other types" do
      attrs = %{command_arguments: 123}
      result = Event.changeset(attrs)

      assert result.command_arguments == ""
    end

    test "sets updated_at to created_at when updated_at not provided" do
      created_at = ~U[2024-03-04 01:00:00Z]
      attrs = %{created_at: created_at}
      result = Event.changeset(attrs)

      # Both should be converted to NaiveDateTime with microsecond precision
      assert result.updated_at == ~N[2024-03-04 01:00:00.000000]
      assert result.created_at == ~N[2024-03-04 01:00:00.000000]
    end

    test "preserves existing updated_at when provided" do
      created_at = ~U[2024-03-04 01:00:00Z]
      updated_at = ~U[2024-03-04 02:00:00Z]
      attrs = %{created_at: created_at, updated_at: updated_at}
      result = Event.changeset(attrs)

      # Both should be converted to NaiveDateTime with microsecond precision
      assert result.updated_at == ~N[2024-03-04 02:00:00.000000]
      assert result.created_at == ~N[2024-03-04 01:00:00.000000]
    end

    test "converts DateTime to NaiveDateTime with microsecond precision" do
      dt = ~U[2024-03-04 01:00:00.123456Z]
      attrs = %{ran_at: dt}
      result = Event.changeset(attrs)

      assert %NaiveDateTime{} = result.ran_at
      assert result.ran_at == ~N[2024-03-04 01:00:00.123456]
      assert elem(result.ran_at.microsecond, 1) == 6
    end

    test "ensures microsecond precision for existing NaiveDateTime" do
      ndt = ~N[2024-03-04 01:00:00.123]
      attrs = %{ran_at: ndt}
      result = Event.changeset(attrs)

      assert %NaiveDateTime{} = result.ran_at
      assert elem(result.ran_at.microsecond, 1) == 6
      assert elem(result.ran_at.microsecond, 0) == 123_000
    end

    test "parses ISO8601 string with Z timezone" do
      attrs = %{ran_at: "2024-03-04T01:00:00.123456Z"}
      result = Event.changeset(attrs)

      assert %NaiveDateTime{} = result.ran_at
      assert result.ran_at == ~N[2024-03-04 01:00:00.123456]
      assert elem(result.ran_at.microsecond, 1) == 6
    end

    test "parses ISO8601 string with + timezone" do
      attrs = %{ran_at: "2024-03-04T01:00:00.123456+00:00"}
      result = Event.changeset(attrs)

      assert %NaiveDateTime{} = result.ran_at
      assert result.ran_at == ~N[2024-03-04 01:00:00.123456]
      assert elem(result.ran_at.microsecond, 1) == 6
    end

    test "parses space-separated datetime string" do
      attrs = %{ran_at: "2024-03-04 01:00:00.123456"}
      result = Event.changeset(attrs)

      assert %NaiveDateTime{} = result.ran_at
      assert result.ran_at == ~N[2024-03-04 01:00:00.123456]
      assert elem(result.ran_at.microsecond, 1) == 6
    end

    test "assumes UTC for string without timezone" do
      attrs = %{ran_at: "2024-03-04T01:00:00.123456"}
      result = Event.changeset(attrs)

      assert %NaiveDateTime{} = result.ran_at
      assert result.ran_at == ~N[2024-03-04 01:00:00.123456]
      assert elem(result.ran_at.microsecond, 1) == 6
    end

    test "preserves nil datetime fields" do
      attrs = %{ran_at: nil}
      result = Event.changeset(attrs)

      assert result.ran_at == nil
    end

    test "preserves non-datetime field types unchanged" do
      attrs = %{ran_at: 123}
      result = Event.changeset(attrs)

      assert result.ran_at == 123
    end

    test "processes all datetime fields" do
      base_time = ~U[2024-03-04 01:00:00.123456Z]

      attrs = %{
        ran_at: base_time,
        created_at: "2024-03-04T02:00:00.654321Z",
        updated_at: ~N[2024-03-04 03:00:00.987]
      }

      result = Event.changeset(attrs)

      assert result.ran_at == ~N[2024-03-04 01:00:00.123456]
      assert result.created_at == ~N[2024-03-04 02:00:00.654321]
      assert result.updated_at == ~N[2024-03-04 03:00:00.987000]

      # Verify microsecond precision
      assert elem(result.ran_at.microsecond, 1) == 6
      assert elem(result.created_at.microsecond, 1) == 6
      assert elem(result.updated_at.microsecond, 1) == 6
    end

    test "handles complex transformation scenario" do
      attrs = %{
        # Should generate ID
        name: "test",
        # Should transform status
        status: :success,
        # Should transform command_arguments
        command_arguments: ["tuist", "generate"],
        # Should convert datetime
        ran_at: ~U[2024-03-04 01:00:00.123456Z],
        created_at: "2024-03-04T01:00:00.123456Z"
        # Should default updated_at from created_at
      }

      result = Event.changeset(attrs)

      # Verify all transformations
      assert is_binary(result.id)
      assert result.status == 0
      assert result.command_arguments == "tuist generate"
      assert result.ran_at == ~N[2024-03-04 01:00:00.123456]
      assert result.created_at == ~N[2024-03-04 01:00:00.123456]
      assert result.updated_at == ~N[2024-03-04 01:00:00.123456]

      # Verify microsecond precision
      assert elem(result.ran_at.microsecond, 1) == 6
      assert elem(result.created_at.microsecond, 1) == 6
      assert elem(result.updated_at.microsecond, 1) == 6
    end

    test "handles empty input gracefully" do
      attrs = %{}
      result = Event.changeset(attrs)

      # Should have generated ID and default command_arguments
      assert is_binary(result.id)
      assert result.command_arguments == ""
      # Should have updated_at set to nil (from created_at which is nil)
      assert result.updated_at == nil
      # Should not have other fields
      refute Map.has_key?(result, :status)
      refute Map.has_key?(result, :ran_at)
      refute Map.has_key?(result, :created_at)
    end

    test "preserves fields not handled by changeset" do
      attrs = %{
        name: "test",
        project_id: 123,
        duration: 5000,
        custom_field: "preserved"
      }

      result = Event.changeset(attrs)

      assert result.name == "test"
      assert result.project_id == 123
      assert result.duration == 5000
      assert result.custom_field == "preserved"
    end
  end
end

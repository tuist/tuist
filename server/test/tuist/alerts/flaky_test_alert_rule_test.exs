defmodule Tuist.Alerts.FlakyTestAlertRuleTest do
  use TuistTestSupport.Cases.DataCase, async: true

  alias Tuist.Alerts.FlakyTestAlertRule
  alias TuistTestSupport.Fixtures.ProjectsFixtures

  describe "changeset/2" do
    test "is valid with valid attributes" do
      # Given
      project = ProjectsFixtures.project_fixture()

      # When
      changeset =
        FlakyTestAlertRule.changeset(%FlakyTestAlertRule{}, %{
          project_id: project.id,
          name: "Flaky Test Alert",
          trigger_threshold: 5,
          slack_channel_id: "C123456",
          slack_channel_name: "flaky-alerts"
        })

      # Then
      assert changeset.valid?
    end

    test "is invalid without project_id" do
      # When
      changeset =
        FlakyTestAlertRule.changeset(%FlakyTestAlertRule{}, %{
          name: "Flaky Test Alert",
          trigger_threshold: 5,
          slack_channel_id: "C123456",
          slack_channel_name: "flaky-alerts"
        })

      # Then
      assert changeset.valid? == false
      assert "can't be blank" in errors_on(changeset).project_id
    end

    test "is invalid without trigger_threshold" do
      # Given
      project = ProjectsFixtures.project_fixture()

      # When
      changeset =
        FlakyTestAlertRule.changeset(%FlakyTestAlertRule{}, %{
          project_id: project.id,
          name: "Flaky Test Alert",
          slack_channel_id: "C123456",
          slack_channel_name: "flaky-alerts"
        })

      # Then
      assert changeset.valid? == false
      assert "can't be blank" in errors_on(changeset).trigger_threshold
    end

    test "is invalid without slack_channel_id" do
      # Given
      project = ProjectsFixtures.project_fixture()

      # When
      changeset =
        FlakyTestAlertRule.changeset(%FlakyTestAlertRule{}, %{
          project_id: project.id,
          name: "Flaky Test Alert",
          trigger_threshold: 5,
          slack_channel_name: "flaky-alerts"
        })

      # Then
      assert changeset.valid? == false
      assert "can't be blank" in errors_on(changeset).slack_channel_id
    end

    test "is invalid without slack_channel_name" do
      # Given
      project = ProjectsFixtures.project_fixture()

      # When
      changeset =
        FlakyTestAlertRule.changeset(%FlakyTestAlertRule{}, %{
          project_id: project.id,
          name: "Flaky Test Alert",
          trigger_threshold: 5,
          slack_channel_id: "C123456"
        })

      # Then
      assert changeset.valid? == false
      assert "can't be blank" in errors_on(changeset).slack_channel_name
    end

    test "is invalid with trigger_threshold <= 0" do
      # Given
      project = ProjectsFixtures.project_fixture()

      # When
      changeset =
        FlakyTestAlertRule.changeset(%FlakyTestAlertRule{}, %{
          project_id: project.id,
          name: "Flaky Test Alert",
          trigger_threshold: 0,
          slack_channel_id: "C123456",
          slack_channel_name: "flaky-alerts"
        })

      # Then
      assert changeset.valid? == false
      assert "must be greater than 0" in errors_on(changeset).trigger_threshold
    end

    test "validates foreign key constraint on project_id" do
      # Given
      non_existent_project_id = 999_999

      # When
      changeset =
        FlakyTestAlertRule.changeset(%FlakyTestAlertRule{}, %{
          project_id: non_existent_project_id,
          name: "Flaky Test Alert",
          trigger_threshold: 5,
          slack_channel_id: "C123456",
          slack_channel_name: "flaky-alerts"
        })

      # Then
      assert changeset.valid?
      {:error, changeset_with_error} = Repo.insert(changeset)
      assert "does not exist" in errors_on(changeset_with_error).project_id
    end

    test "defaults name to Untitled" do
      # Given
      project = ProjectsFixtures.project_fixture()

      # When
      changeset =
        FlakyTestAlertRule.changeset(%FlakyTestAlertRule{}, %{
          project_id: project.id,
          trigger_threshold: 5,
          slack_channel_id: "C123456",
          slack_channel_name: "flaky-alerts"
        })

      # Then
      assert changeset.valid?
      {:ok, rule} = Repo.insert(changeset)
      assert rule.name == "Untitled"
    end
  end
end

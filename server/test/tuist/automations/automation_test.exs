defmodule Tuist.Automations.AutomationTest do
  use TuistTestSupport.Cases.DataCase, async: true

  alias Tuist.Automations.Automation
  alias TuistTestSupport.Fixtures.ProjectsFixtures

  defp valid_attrs(project, overrides \\ %{}) do
    Map.merge(
      %{
        "project_id" => project.id,
        "name" => "Auto-quarantine flaky tests",
        "automation_type" => "flakiness_rate",
        "config" => %{"threshold" => 10, "window" => "30d"},
        "trigger_actions" => [%{"type" => "change_state", "state" => "muted"}]
      },
      overrides
    )
  end

  describe "changeset/2" do
    test "is valid with valid attributes" do
      project = ProjectsFixtures.project_fixture()
      changeset = Automation.changeset(%Automation{}, valid_attrs(project))
      assert changeset.valid?
    end

    test "requires project_id, name, automation_type, trigger_actions" do
      changeset = Automation.changeset(%Automation{}, %{})
      refute changeset.valid?
      errors = errors_on(changeset)
      assert "can't be blank" in errors.project_id
      assert "can't be blank" in errors.name
      assert "can't be blank" in errors.automation_type
      assert "can't be blank" in errors.trigger_actions
    end

    test "rejects unknown automation_type" do
      project = ProjectsFixtures.project_fixture()
      changeset = Automation.changeset(%Automation{}, valid_attrs(project, %{"automation_type" => "bogus"}))
      refute changeset.valid?
      assert errors_on(changeset).automation_type
    end

    test "accepts flaky_run_count automation_type with integer threshold" do
      project = ProjectsFixtures.project_fixture()

      changeset =
        Automation.changeset(
          %Automation{},
          valid_attrs(project, %{
            "automation_type" => "flaky_run_count",
            "config" => %{"threshold" => 3, "window" => "30d"}
          })
        )

      assert changeset.valid?
    end

    test "rejects flakiness_rate config with threshold out of range" do
      project = ProjectsFixtures.project_fixture()

      changeset =
        Automation.changeset(
          %Automation{},
          valid_attrs(project, %{"config" => %{"threshold" => 200, "window" => "30d"}})
        )

      refute changeset.valid?
      assert errors_on(changeset).config
    end

    test "rejects flakiness_rate config without window" do
      project = ProjectsFixtures.project_fixture()

      changeset =
        Automation.changeset(
          %Automation{},
          valid_attrs(project, %{"config" => %{"threshold" => 10}})
        )

      refute changeset.valid?
      assert errors_on(changeset).config
    end
  end

  describe "trigger_actions validation" do
    test "accepts a change_state action with valid state" do
      project = ProjectsFixtures.project_fixture()

      changeset =
        Automation.changeset(
          %Automation{},
          valid_attrs(project, %{
            "trigger_actions" => [%{"type" => "change_state", "state" => "enabled"}]
          })
        )

      assert changeset.valid?
    end

    test "rejects change_state action with invalid state" do
      project = ProjectsFixtures.project_fixture()

      changeset =
        Automation.changeset(
          %Automation{},
          valid_attrs(project, %{
            "trigger_actions" => [%{"type" => "change_state", "state" => "bogus"}]
          })
        )

      refute changeset.valid?
      assert "contains invalid actions" in errors_on(changeset).trigger_actions
    end

    test "accepts a send_slack action with channel and message" do
      project = ProjectsFixtures.project_fixture()

      changeset =
        Automation.changeset(
          %Automation{},
          valid_attrs(project, %{
            "trigger_actions" => [
              %{"type" => "send_slack", "channel" => "C123", "message" => "hi"}
            ]
          })
        )

      assert changeset.valid?
    end

    test "rejects send_slack action with empty channel" do
      project = ProjectsFixtures.project_fixture()

      changeset =
        Automation.changeset(
          %Automation{},
          valid_attrs(project, %{
            "trigger_actions" => [%{"type" => "send_slack", "channel" => "", "message" => "hi"}]
          })
        )

      refute changeset.valid?
    end

    test "rejects send_slack action with empty message" do
      project = ProjectsFixtures.project_fixture()

      changeset =
        Automation.changeset(
          %Automation{},
          valid_attrs(project, %{
            "trigger_actions" => [%{"type" => "send_slack", "channel" => "C123", "message" => ""}]
          })
        )

      refute changeset.valid?
    end

    test "accepts add_label and remove_label actions" do
      project = ProjectsFixtures.project_fixture()

      changeset =
        Automation.changeset(
          %Automation{},
          valid_attrs(project, %{
            "trigger_actions" => [%{"type" => "add_label", "label" => "flaky"}],
            "recovery_enabled" => true,
            "recovery_config" => %{"window" => "14d"},
            "recovery_actions" => [%{"type" => "remove_label", "label" => "flaky"}]
          })
        )

      assert changeset.valid?
    end

    test "rejects add_label without a label" do
      project = ProjectsFixtures.project_fixture()

      changeset =
        Automation.changeset(
          %Automation{},
          valid_attrs(project, %{
            "trigger_actions" => [%{"type" => "add_label"}]
          })
        )

      refute changeset.valid?
    end

    test "rejects more than one change_state action in trigger_actions" do
      project = ProjectsFixtures.project_fixture()

      changeset =
        Automation.changeset(
          %Automation{},
          valid_attrs(project, %{
            "trigger_actions" => [
              %{"type" => "change_state", "state" => "muted"},
              %{"type" => "change_state", "state" => "enabled"}
            ]
          })
        )

      refute changeset.valid?
      assert "can only contain one change_state action" in errors_on(changeset).trigger_actions
    end

    test "rejects duplicate add_label with same label" do
      project = ProjectsFixtures.project_fixture()

      changeset =
        Automation.changeset(
          %Automation{},
          valid_attrs(project, %{
            "trigger_actions" => [
              %{"type" => "add_label", "label" => "flaky"},
              %{"type" => "add_label", "label" => "flaky"}
            ]
          })
        )

      refute changeset.valid?
      assert "can only contain one add_label action per label" in errors_on(changeset).trigger_actions
    end

    test "allows add_label with different labels" do
      project = ProjectsFixtures.project_fixture()

      changeset =
        Automation.changeset(
          %Automation{},
          valid_attrs(project, %{
            "trigger_actions" => [
              %{"type" => "add_label", "label" => "flaky"},
              %{"type" => "add_label", "label" => "slow"}
            ]
          })
        )

      assert changeset.valid?
    end

    test "rejects unknown action type" do
      project = ProjectsFixtures.project_fixture()

      changeset =
        Automation.changeset(
          %Automation{},
          valid_attrs(project, %{"trigger_actions" => [%{"type" => "fly_to_moon"}]})
        )

      refute changeset.valid?
    end
  end

  describe "foreign key" do
    test "rejects nonexistent project_id" do
      changeset = Automation.changeset(%Automation{}, valid_attrs(%{id: 999_999}))
      assert changeset.valid?
      {:error, changeset_with_error} = Repo.insert(changeset)
      assert "does not exist" in errors_on(changeset_with_error).project_id
    end
  end
end

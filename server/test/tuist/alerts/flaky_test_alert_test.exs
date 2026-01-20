defmodule Tuist.Alerts.FlakyTestAlertTest do
  use TuistTestSupport.Cases.DataCase, async: true

  alias Tuist.Alerts.FlakyTestAlert
  alias TuistTestSupport.Fixtures.AlertsFixtures

  describe "changeset/2" do
    test "is valid with valid attributes" do
      # Given
      rule = AlertsFixtures.flaky_test_alert_rule_fixture()

      # When
      changeset =
        FlakyTestAlert.changeset(%FlakyTestAlert{}, %{
          flaky_test_alert_rule_id: rule.id,
          flaky_runs_count: 5,
          test_case_id: Ecto.UUID.generate(),
          test_case_name: "testExample",
          test_case_module_name: "MyTests",
          test_case_suite_name: "TestSuite"
        })

      # Then
      assert changeset.valid?
    end

    test "is valid without test case details" do
      # Given
      rule = AlertsFixtures.flaky_test_alert_rule_fixture()

      # When
      changeset =
        FlakyTestAlert.changeset(%FlakyTestAlert{}, %{
          flaky_test_alert_rule_id: rule.id,
          flaky_runs_count: 5
        })

      # Then
      assert changeset.valid?
    end

    test "is invalid without flaky_test_alert_rule_id" do
      # When
      changeset =
        FlakyTestAlert.changeset(%FlakyTestAlert{}, %{
          flaky_runs_count: 5
        })

      # Then
      assert changeset.valid? == false
      assert "can't be blank" in errors_on(changeset).flaky_test_alert_rule_id
    end

    test "is invalid without flaky_runs_count" do
      # Given
      rule = AlertsFixtures.flaky_test_alert_rule_fixture()

      # When
      changeset =
        FlakyTestAlert.changeset(%FlakyTestAlert{}, %{
          flaky_test_alert_rule_id: rule.id
        })

      # Then
      assert changeset.valid? == false
      assert "can't be blank" in errors_on(changeset).flaky_runs_count
    end

    test "validates foreign key constraint on flaky_test_alert_rule_id" do
      # Given
      non_existent_rule_id = Ecto.UUID.generate()

      # When
      changeset =
        FlakyTestAlert.changeset(%FlakyTestAlert{}, %{
          flaky_test_alert_rule_id: non_existent_rule_id,
          flaky_runs_count: 5
        })

      # Then
      assert changeset.valid?
      {:error, changeset_with_error} = Repo.insert(changeset)
      assert "does not exist" in errors_on(changeset_with_error).flaky_test_alert_rule_id
    end

    test "allows setting inserted_at" do
      # Given
      rule = AlertsFixtures.flaky_test_alert_rule_fixture()
      custom_time = ~U[2024-01-15 10:00:00Z]

      # When
      changeset =
        FlakyTestAlert.changeset(%FlakyTestAlert{}, %{
          flaky_test_alert_rule_id: rule.id,
          flaky_runs_count: 5,
          inserted_at: custom_time
        })

      # Then
      assert changeset.valid?
      {:ok, alert} = Repo.insert(changeset)
      assert alert.inserted_at == custom_time
    end
  end
end

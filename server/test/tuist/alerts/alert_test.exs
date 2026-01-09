defmodule Tuist.Alerts.AlertTest do
  use TuistTestSupport.Cases.DataCase, async: true

  alias Tuist.Alerts.Alert
  alias TuistTestSupport.Fixtures.AlertsFixtures

  describe "changeset/2" do
    test "is valid with valid attributes" do
      # Given
      alert_rule = AlertsFixtures.alert_rule_fixture()

      # When
      changeset =
        Alert.changeset(%Alert{}, %{
          alert_rule_id: alert_rule.id,
          current_value: 1200.0,
          previous_value: 1000.0
        })

      # Then
      assert changeset.valid?
    end

    test "is invalid without alert_rule_id" do
      # When
      changeset =
        Alert.changeset(%Alert{}, %{
          current_value: 1200.0,
          previous_value: 1000.0
        })

      # Then
      assert changeset.valid? == false
      assert "can't be blank" in errors_on(changeset).alert_rule_id
    end

    test "is invalid without current_value" do
      # Given
      alert_rule = AlertsFixtures.alert_rule_fixture()

      # When
      changeset =
        Alert.changeset(%Alert{}, %{
          alert_rule_id: alert_rule.id,
          previous_value: 1000.0
        })

      # Then
      assert changeset.valid? == false
      assert "can't be blank" in errors_on(changeset).current_value
    end

    test "is invalid without previous_value" do
      # Given
      alert_rule = AlertsFixtures.alert_rule_fixture()

      # When
      changeset =
        Alert.changeset(%Alert{}, %{
          alert_rule_id: alert_rule.id,
          current_value: 1200.0
        })

      # Then
      assert changeset.valid? == false
      assert "can't be blank" in errors_on(changeset).previous_value
    end

    test "validates foreign key constraint on alert_rule_id" do
      # Given
      non_existent_id = Ecto.UUID.generate()

      # When
      changeset =
        Alert.changeset(%Alert{}, %{
          alert_rule_id: non_existent_id,
          current_value: 1200.0,
          previous_value: 1000.0
        })

      # Then
      assert changeset.valid?
      {:error, changeset_with_error} = Repo.insert(changeset)
      assert "does not exist" in errors_on(changeset_with_error).alert_rule_id
    end
  end
end

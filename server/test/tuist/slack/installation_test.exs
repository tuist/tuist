defmodule Tuist.Slack.InstallationTest do
  use TuistTestSupport.Cases.DataCase, async: true

  alias Tuist.Slack.Installation
  alias TuistTestSupport.Fixtures.AccountsFixtures
  alias TuistTestSupport.Fixtures.SlackFixtures

  describe "changeset/2" do
    test "is valid with valid attributes" do
      # Given
      user = AccountsFixtures.user_fixture()
      user = Repo.preload(user, :account)

      # When
      changeset =
        Installation.changeset(%Installation{}, %{
          account_id: user.account.id,
          team_id: "T12345",
          team_name: "Test Workspace",
          access_token: "xoxb-test-token",
          bot_user_id: "U12345"
        })

      # Then
      assert changeset.valid?
    end

    test "is invalid without account_id" do
      # When
      changeset =
        Installation.changeset(%Installation{}, %{
          team_id: "T12345",
          access_token: "xoxb-test-token"
        })

      # Then
      assert changeset.valid? == false
      assert "can't be blank" in errors_on(changeset).account_id
    end

    test "is invalid without team_id" do
      # When
      changeset =
        Installation.changeset(%Installation{}, %{
          account_id: 1,
          access_token: "xoxb-test-token"
        })

      # Then
      assert changeset.valid? == false
      assert "can't be blank" in errors_on(changeset).team_id
    end

    test "is invalid without access_token" do
      # When
      changeset =
        Installation.changeset(%Installation{}, %{
          account_id: 1,
          team_id: "T12345"
        })

      # Then
      assert changeset.valid? == false
      assert "can't be blank" in errors_on(changeset).access_token
    end

    test "is valid without optional fields" do
      # Given
      user = AccountsFixtures.user_fixture()
      user = Repo.preload(user, :account)

      # When
      changeset =
        Installation.changeset(%Installation{}, %{
          account_id: user.account.id,
          team_id: "T12345",
          access_token: "xoxb-test-token"
        })

      # Then
      assert changeset.valid?
    end

    test "enforces unique constraint on account_id" do
      # Given
      installation = SlackFixtures.slack_installation_fixture()

      # When
      changeset =
        Installation.changeset(%Installation{}, %{
          account_id: installation.account_id,
          team_id: "T99999",
          access_token: "xoxb-different-token"
        })

      {:error, changeset_with_error} = Repo.insert(changeset)

      # Then
      assert "has already been taken" in errors_on(changeset_with_error).account_id
    end

    test "enforces unique constraint on team_id" do
      # Given
      installation = SlackFixtures.slack_installation_fixture()
      user = AccountsFixtures.user_fixture()
      user = Repo.preload(user, :account)

      # When
      changeset =
        Installation.changeset(%Installation{}, %{
          account_id: user.account.id,
          team_id: installation.team_id,
          access_token: "xoxb-different-token"
        })

      {:error, changeset_with_error} = Repo.insert(changeset)

      # Then
      assert "has already been taken" in errors_on(changeset_with_error).team_id
    end

    test "validates foreign key constraint on account_id" do
      # Given
      non_existent_account_id = 999_999

      # When
      changeset =
        Installation.changeset(%Installation{}, %{
          account_id: non_existent_account_id,
          team_id: "T12345",
          access_token: "xoxb-test-token"
        })

      # Then
      assert changeset.valid?
      {:error, changeset_with_error} = Repo.insert(changeset)
      assert "does not exist" in errors_on(changeset_with_error).account_id
    end

    test "allows different accounts with different team_ids" do
      # Given
      user1 = AccountsFixtures.user_fixture()
      user1 = Repo.preload(user1, :account)
      user2 = AccountsFixtures.user_fixture()
      user2 = Repo.preload(user2, :account)

      # When
      {:ok, _installation1} =
        %Installation{}
        |> Installation.changeset(%{
          account_id: user1.account.id,
          team_id: "T11111",
          access_token: "xoxb-token-1"
        })
        |> Repo.insert()

      {:ok, _installation2} =
        %Installation{}
        |> Installation.changeset(%{
          account_id: user2.account.id,
          team_id: "T22222",
          access_token: "xoxb-token-2"
        })
        |> Repo.insert()

      # Then - Both inserts should succeed
      assert true
    end
  end
end

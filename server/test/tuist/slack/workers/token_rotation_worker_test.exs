defmodule Tuist.Slack.Workers.TokenRotationWorkerTest do
  use TuistTestSupport.Cases.DataCase, async: true
  use Mimic

  alias Tuist.Slack.Client
  alias Tuist.Slack.Installation
  alias Tuist.Slack.Workers.TokenRotationWorker
  alias TuistTestSupport.Fixtures.SlackFixtures

  test "exchanges long-lived tokens and refreshes tokens expiring within six hours, leaving the rest" do
    legacy = SlackFixtures.slack_installation_fixture(access_token: "xoxb-legacy")

    expiring =
      SlackFixtures.slack_installation_fixture(
        access_token: "xoxe.xoxb-expiring",
        refresh_token: "xoxe-1-expiring",
        access_token_expires_at: DateTime.add(DateTime.utc_now(), 5 * 60 * 60, :second)
      )

    fresh =
      SlackFixtures.slack_installation_fixture(
        access_token: "xoxe.xoxb-fresh",
        refresh_token: "xoxe-1-fresh",
        access_token_expires_at: DateTime.add(DateTime.utc_now(), 7 * 60 * 60, :second)
      )

    expect(Client, :exchange_token, fn "xoxb-legacy" ->
      {:ok, %{access_token: "xoxe.xoxb-exchanged", refresh_token: "xoxe-1-exchanged", expires_in: 43_200}}
    end)

    expect(Client, :refresh_token, fn "xoxe-1-expiring" ->
      {:ok, %{access_token: "xoxe.xoxb-refreshed", refresh_token: "xoxe-1-refreshed", expires_in: 43_200}}
    end)

    assert :ok = TokenRotationWorker.perform(%Oban.Job{args: %{}})

    assert %Installation{access_token: "xoxe.xoxb-exchanged", refresh_token: "xoxe-1-exchanged"} =
             Repo.get!(Installation, legacy.id)

    assert %Installation{access_token: "xoxe.xoxb-refreshed", refresh_token: "xoxe-1-refreshed"} =
             Repo.get!(Installation, expiring.id)

    assert %Installation{access_token: "xoxe.xoxb-fresh", refresh_token: "xoxe-1-fresh"} =
             Repo.get!(Installation, fresh.id)
  end

  test "continues with other installations when one rotation fails" do
    failing = SlackFixtures.slack_installation_fixture(access_token: "xoxb-failing")

    expiring =
      SlackFixtures.slack_installation_fixture(
        access_token: "xoxe.xoxb-expiring",
        refresh_token: "xoxe-1-expiring",
        access_token_expires_at: DateTime.add(DateTime.utc_now(), 60, :second)
      )

    expect(Client, :exchange_token, fn "xoxb-failing" -> {:error, "token_already_exchanged"} end)

    expect(Sentry, :capture_message, fn "Slack token exchange failed permanently", opts ->
      assert opts[:extra].reason == "token_already_exchanged"
      assert opts[:extra].installation_id == failing.id
      :ok
    end)

    expect(Client, :refresh_token, fn "xoxe-1-expiring" ->
      {:ok, %{access_token: "xoxe.xoxb-refreshed", refresh_token: "xoxe-1-refreshed", expires_in: 43_200}}
    end)

    assert :ok = TokenRotationWorker.perform(%Oban.Job{args: %{}})

    assert Repo.get!(Installation, failing.id).access_token == "xoxb-failing"
    assert Repo.get!(Installation, expiring.id).refresh_token == "xoxe-1-refreshed"
  end

  test "exchanges at most five tokens per run, not counting failed exchanges" do
    failing = SlackFixtures.slack_installation_fixture(access_token: "xoxb-dead")
    legacy = for n <- 1..6, do: SlackFixtures.slack_installation_fixture(access_token: "xoxb-#{n}")

    stub(Sentry, :capture_message, fn _, _ -> :ok end)

    expect(Client, :exchange_token, 6, fn
      "xoxb-dead" ->
        {:error, "invalid_auth"}

      token ->
        {:ok, %{access_token: "xoxe.#{token}", refresh_token: "xoxe-1-#{token}", expires_in: 43_200}}
    end)

    assert :ok = TokenRotationWorker.perform(%Oban.Job{args: %{}})

    exchanged = Enum.count(legacy, &Repo.get!(Installation, &1.id).refresh_token)
    assert exchanged == 5
    assert is_nil(Repo.get!(Installation, failing.id).refresh_token)
  end

  test "stops exchanging at the first token_rotation_not_enabled" do
    for n <- 1..3, do: SlackFixtures.slack_installation_fixture(access_token: "xoxb-#{n}")
    reject(Sentry, :capture_message, 2)

    expect(Client, :exchange_token, 1, fn _ -> {:error, "token_rotation_not_enabled"} end)

    assert :ok = TokenRotationWorker.perform(%Oban.Job{args: %{}})
  end
end

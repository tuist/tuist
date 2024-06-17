defmodule TuistCloud.Billing.UpdateRemoteCacheHitWorkerTest do
  alias TuistCloud.ProjectsFixtures
  alias TuistCloud.Accounts.Account
  alias TuistCloud.AccountsFixtures
  alias TuistCloud.CommandEventsFixtures
  alias TuistCloud.Billing.UpdateRemoteCacheHitWorker
  use TuistCloud.DataCase, async: true
  use Mimic

  test "updates the remote cache hit for accounts with subscriptions" do
    # Given
    %{account: account} = AccountsFixtures.user_fixture(preloads: [:account])
    project = ProjectsFixtures.project_fixture(account_id: account.id)
    customer_id = "customer_id"

    account
    |> Account.update_changeset(%{plan: :pro, customer_id: customer_id})
    |> TuistCloud.Repo.update!()

    date = ~U[2024-04-30 10:20:30Z]
    TuistCloud.Time |> stub(:utc_now, fn -> date end)

    CommandEventsFixtures.command_event_fixture(
      project_id: project.id,
      name: "generate",
      duration: 1500,
      created_at: date |> Timex.shift(days: -1),
      remote_test_target_hits: ["target1", "target2"]
    )

    CommandEventsFixtures.command_event_fixture(
      project_id: project.id,
      name: "build",
      duration: 1500,
      created_at: date |> Timex.shift(days: -1),
      remote_cache_target_hits: ["target1", "target2"]
    )

    CommandEventsFixtures.command_event_fixture(
      project_id: project.id,
      name: "generate",
      duration: 1500,
      created_at: date |> Timex.shift(days: -2),
      remote_cache_target_hits: ["target1", "target2"]
    )

    TuistCloud.Billing
    |> expect(:update_remote_cache_hit_meter, fn {^customer_id, 2} -> :ok end)

    # When
    UpdateRemoteCacheHitWorker.perform(%{})
  end
end

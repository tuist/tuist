defmodule Tuist.Billing.UpdateAllCustomersRemoteCacheHitsCountWorkerTest do
  use TuistTestSupport.Cases.DataCase, async: false
  use Mimic

  alias Tuist.Billing.UpdateAllCustomersRemoteCacheHitsCountWorker
  alias TuistTestSupport.Fixtures.AccountsFixtures
  alias TuistTestSupport.Fixtures.CommandEventsFixtures
  alias TuistTestSupport.Fixtures.ProjectsFixtures

  setup :set_mimic_from_context

  test "updates the remote cache hit for accounts with subscriptions" do
    # Given
    first_account_customer_id = "account-1-#{UUIDv7.generate()}"
    second_account_customer_id = "account-2=#{UUIDv7.generate()}"

    %{account: first_account} =
      AccountsFixtures.user_fixture(customer_id: first_account_customer_id)

    %{account: second_account} =
      AccountsFixtures.user_fixture(customer_id: second_account_customer_id)

    first_account_project = ProjectsFixtures.project_fixture(account_id: first_account.id)
    second_account_project = ProjectsFixtures.project_fixture(account_id: second_account.id)

    date = ~U[2024-04-30 10:20:30Z]
    stub(DateTime, :utc_now, fn -> date end)

    CommandEventsFixtures.command_event_fixture(
      project_id: first_account_project.id,
      name: "generate",
      duration: 1500,
      created_at: ~U[2024-04-29 10:20:30Z],
      remote_test_target_hits: ["target1", "target2"]
    )

    CommandEventsFixtures.command_event_fixture(
      project_id: second_account_project.id,
      name: "generate",
      duration: 1500,
      created_at: ~U[2024-04-29 10:20:31Z],
      remote_test_target_hits: ["target1", "target2"]
    )

    CommandEventsFixtures.command_event_fixture(
      project_id: first_account_project.id,
      name: "generate",
      duration: 1500,
      created_at: ~U[2024-04-27 10:20:33Z],
      remote_cache_target_hits: ["target1", "target2"]
    )

    expect(Tuist.Billing, :update_remote_cache_hit_meter, fn {^first_account_customer_id, 1} -> :ok end)
    expect(Tuist.Billing, :update_remote_cache_hit_meter, fn {^second_account_customer_id, 1} -> :ok end)

    # When
    %{page_size: 1} |> UpdateAllCustomersRemoteCacheHitsCountWorker.new() |> Oban.insert()
  end
end

defmodule Tuist.Billing.Workers.SyncStripeMetersWorkerWorkerTest do
  use TuistTestSupport.Cases.DataCase, async: false
  use Mimic

  alias Tuist.Billing.Workers.SyncCustomerStripeMetersWorker
  alias Tuist.Billing.Workers.SyncStripeMetersWorker
  alias TuistTestSupport.Fixtures.AccountsFixtures
  alias TuistTestSupport.Fixtures.CommandEventsFixtures
  alias TuistTestSupport.Fixtures.ProjectsFixtures

  setup :set_mimic_from_context

  test "enqueues SyncCustomerStripeMetersWorker jobs for each billable customer with cache events" do
    first_account_customer_id = "account-1-#{UUIDv7.generate()}"
    second_account_customer_id = "account-2-#{UUIDv7.generate()}"

    %{account: first_account} =
      AccountsFixtures.user_fixture(customer_id: first_account_customer_id)

    %{account: second_account} =
      AccountsFixtures.user_fixture(customer_id: second_account_customer_id)

    # Account without customer_id should not be included
    %{account: third_account} = AccountsFixtures.user_fixture(customer_id: nil)

    first_account_project = ProjectsFixtures.project_fixture(account_id: first_account.id)
    second_account_project = ProjectsFixtures.project_fixture(account_id: second_account.id)
    ProjectsFixtures.project_fixture(account_id: third_account.id)

    date = ~U[2024-04-30 10:20:30Z]
    stub(DateTime, :utc_now, fn -> date end)

    # Create events for yesterday (2024-04-29) for all accounts
    CommandEventsFixtures.command_event_fixture(
      project_id: first_account_project.id,
      name: "generate",
      duration: 1500,
      ran_at: ~U[2024-04-29 10:20:30Z],
      remote_test_target_hits: ["target1", "target2"]
    )

    CommandEventsFixtures.command_event_fixture(
      project_id: second_account_project.id,
      name: "generate",
      duration: 1500,
      ran_at: ~U[2024-04-29 10:20:31Z],
      remote_test_target_hits: ["target1", "target2"]
    )

    # When
    Oban.Testing.with_testing_mode(:manual, fn ->
      SyncStripeMetersWorker.perform(%Oban.Job{args: %{}})

      # Then
      assert_enqueued(
        worker: SyncCustomerStripeMetersWorker,
        args: %{customer_id: first_account_customer_id}
      )

      assert_enqueued(
        worker: SyncCustomerStripeMetersWorker,
        args: %{customer_id: second_account_customer_id}
      )

      all_jobs = all_enqueued(worker: SyncCustomerStripeMetersWorker)
      assert length(all_jobs) == 2

      customer_ids_in_jobs = all_jobs |> Enum.map(& &1.args["customer_id"]) |> Enum.sort()
      expected_customer_ids = Enum.sort([first_account_customer_id, second_account_customer_id])
      assert customer_ids_in_jobs == expected_customer_ids
    end)
  end

  test "enqueues SyncCustomerStripeMetersWorker jobs for each billable customer with LLM usage" do
    # Given
    customer_with_tokens = "customer-tokens-#{UUIDv7.generate()}"
    %{account: account_with_tokens} = AccountsFixtures.user_fixture(customer_id: customer_with_tokens)

    date = ~U[2024-04-30 10:20:30Z]
    stub(DateTime, :utc_now, fn -> date end)

    {:ok, _} =
      Tuist.Billing.create_token_usage(%{
        input_tokens: 100,
        output_tokens: 50,
        model: "gpt-4",
        feature: "qa",
        feature_resource_id: UUIDv7.generate(),
        account_id: account_with_tokens.id,
        timestamp: ~U[2024-04-29 15:00:00Z]
      })

    # When
    Oban.Testing.with_testing_mode(:manual, fn ->
      SyncStripeMetersWorker.perform(%Oban.Job{args: %{}})

      # Then
      assert_enqueued(
        worker: SyncCustomerStripeMetersWorker,
        args: %{customer_id: customer_with_tokens}
      )

      all_jobs = all_enqueued(worker: SyncCustomerStripeMetersWorker)
      assert length(all_jobs) == 1
    end)
  end

  test "enqueues each customer only once when they have both cache events and LLM usage" do
    # Given
    customer_id = "customer-both-#{UUIDv7.generate()}"
    %{account: account} = AccountsFixtures.user_fixture(customer_id: customer_id)

    project = ProjectsFixtures.project_fixture(account_id: account.id)

    date = ~U[2024-04-30 10:20:30Z]
    stub(DateTime, :utc_now, fn -> date end)

    CommandEventsFixtures.command_event_fixture(
      project_id: project.id,
      name: "generate",
      duration: 1000,
      ran_at: ~U[2024-04-29 09:00:00Z],
      remote_cache_target_hits: ["t1"]
    )

    {:ok, _} =
      Tuist.Billing.create_token_usage(%{
        input_tokens: 42,
        output_tokens: 21,
        model: "gpt-4",
        feature: "qa",
        feature_resource_id: UUIDv7.generate(),
        account_id: account.id,
        timestamp: ~U[2024-04-29 12:00:00Z]
      })

    # When
    Oban.Testing.with_testing_mode(:manual, fn ->
      SyncStripeMetersWorker.perform(%Oban.Job{args: %{}})

      # Then
      assert_enqueued(worker: SyncCustomerStripeMetersWorker, args: %{customer_id: customer_id})

      all_jobs = all_enqueued(worker: SyncCustomerStripeMetersWorker)
      assert length(all_jobs) == 1
    end)
  end
end

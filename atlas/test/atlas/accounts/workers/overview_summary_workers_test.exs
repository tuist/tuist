defmodule Atlas.Accounts.Workers.OverviewSummaryWorkersTest do
  use Atlas.DataCase, async: true
  use Oban.Testing, repo: Atlas.Repo

  alias Atlas.Accounts.Account
  alias Atlas.Accounts.Workers.ScheduleOverviewSummaries
  alias Atlas.Accounts.Workers.UpdateOverviewSummary
  alias Atlas.Audit

  describe "UpdateOverviewSummary.perform/1" do
    test "returns :ok when the refresh succeeds" do
      refresh = fn account_id ->
        assert account_id == "account-123"
        {:ok, %{id: account_id}}
      end

      assert :ok =
               UpdateOverviewSummary.perform(%Oban.Job{args: %{"account_id" => "account-123"}},
                 refresh: refresh
               )
    end

    test "runs refreshes with a worker audit context" do
      refresh = fn _account_id ->
        assert Audit.current_context().interface == "worker"
        {:ok, %{}}
      end

      assert :ok =
               UpdateOverviewSummary.perform(%Oban.Job{args: %{"account_id" => "account-123"}}, refresh: refresh)
    end

    test "cancels when the account no longer exists" do
      assert {:cancel, :account_not_found} =
               perform_job(UpdateOverviewSummary, %{"account_id" => Atlas.UUIDv7.generate()})
    end

    test "cancels when the LLM is not configured" do
      account = insert_account!(%{account_key: "account:no-llm", name: "No LLM"})

      assert {:cancel, :llm_not_configured} =
               perform_job(UpdateOverviewSummary, %{"account_id" => account.id})
    end

    test "cancels permanent language model provider errors" do
      refresh = fn _account_id -> {:error, {:api_error, %{status: 402, body: %{"error" => "credit_limit"}}}} end

      assert {:cancel, :llm_credit_limit} =
               UpdateOverviewSummary.perform(%Oban.Job{args: %{"account_id" => "account-123"}},
                 refresh: refresh
               )
    end
  end

  describe "ScheduleOverviewSummaries.perform/1" do
    test "returns zero when there are no accounts to schedule" do
      assert {:ok, 0} = perform_job(ScheduleOverviewSummaries, %{})
    end

    test "stops scheduling when a job insert fails" do
      error_changeset =
        %Oban.Job{}
        |> Ecto.Changeset.change()
        |> Ecto.Changeset.add_error(:args, "is invalid")

      insert = fn
        %Ecto.Changeset{changes: %{args: %{account_id: "first"}}} = changeset ->
          {:ok, changeset}

        %Ecto.Changeset{changes: %{args: %{account_id: "second"}}} ->
          {:error, error_changeset}
      end

      assert {:error, ^error_changeset} =
               ScheduleOverviewSummaries.perform(%Oban.Job{},
                 list_account_ids: fn -> ["first", "second"] end,
                 insert: insert
               )
    end

    test "enqueues one overview update job per account" do
      first = insert_account!(%{account_key: "account:first", name: "First"})
      second = insert_account!(%{account_key: "account:second", name: "Second"})

      assert {:ok, 2} = perform_job(ScheduleOverviewSummaries, %{})

      assert_enqueued(worker: UpdateOverviewSummary, args: %{"account_id" => first.id})
      assert_enqueued(worker: UpdateOverviewSummary, args: %{"account_id" => second.id})
    end
  end

  defp insert_account!(attrs) do
    defaults = %{
      account_key: "account:#{System.unique_integer([:positive])}",
      name: "Account",
      segment: :lead
    }

    %Account{}
    |> Account.changeset(Map.merge(defaults, attrs))
    |> Repo.insert!()
  end
end

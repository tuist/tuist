defmodule Atlas.Accounts.Workers.OutcomeProposalWorkersTest do
  use Atlas.DataCase, async: true
  use Oban.Testing, repo: Atlas.Repo

  alias Atlas.Accounts.Workers.GenerateOutcomeProposals
  alias Atlas.Accounts.Workers.ScheduleOutcomeProposals

  test "generation worker cancels jobs from the retired customer outcomes feature" do
    assert {:cancel, :customer_outcomes_retired} =
             perform_job(GenerateOutcomeProposals, %{"account_id" => "account-123"})
  end

  test "scheduler cancels jobs from the retired customer outcomes feature" do
    assert {:cancel, :customer_outcomes_retired} = perform_job(ScheduleOutcomeProposals, %{})
  end
end

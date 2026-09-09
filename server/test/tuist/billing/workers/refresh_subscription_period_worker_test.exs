defmodule Tuist.Billing.Workers.RefreshSubscriptionPeriodWorkerTest do
  use TuistTestSupport.Cases.DataCase, async: true
  use Mimic

  alias Tuist.Billing
  alias Tuist.Billing.Workers.RefreshSubscriptionPeriodWorker

  test "refreshes the subscription it was given" do
    # Given
    expect(Billing, :refresh_subscription_period, fn "sub_id" -> :ok end)

    # When / Then
    assert :ok == RefreshSubscriptionPeriodWorker.perform(%Oban.Job{args: %{"subscription_id" => "sub_id"}})
  end

  test "fails so the job retries when the period could not be read" do
    # Given
    expect(Billing, :refresh_subscription_period, fn "sub_id" -> {:error, :billing_period_unavailable} end)

    # When / Then
    assert {:error, :billing_period_unavailable} ==
             RefreshSubscriptionPeriodWorker.perform(%Oban.Job{args: %{"subscription_id" => "sub_id"}})
  end
end

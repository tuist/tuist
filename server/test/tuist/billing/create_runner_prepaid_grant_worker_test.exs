defmodule Tuist.Billing.Workers.CreateRunnerPrepaidGrantWorkerTest do
  use TuistTestSupport.Cases.DataCase, async: true
  use Mimic

  alias Tuist.Billing.Workers.CreateRunnerPrepaidGrantWorker
  alias Tuist.Runners.Prepaid

  setup do
    stub(Stripe.Invoice, :retrieve, fn invoice_id -> {:ok, %Stripe.Invoice{id: invoice_id}} end)
    :ok
  end

  defp job(args, attempt \\ 1), do: %Oban.Job{id: 1, args: args, attempt: attempt}

  test "re-reads the invoice from Stripe rather than trusting the webhook's copy" do
    expect(Stripe.Invoice, :retrieve, fn "in_1" -> {:ok, %Stripe.Invoice{id: "in_1"}} end)

    expect(Prepaid, :grant_for_paid_invoice, fn %Stripe.Invoice{id: "in_1"} ->
      {:ok, [%{id: "credgr_1"}]}
    end)

    assert :ok = CreateRunnerPrepaidGrantWorker.perform(job(%{"invoice_id" => "in_1"}))
  end

  test "treats an invoice with no prepaid line as done" do
    stub(Prepaid, :grant_for_paid_invoice, fn _invoice -> {:ok, :not_prepaid} end)

    assert :ok = CreateRunnerPrepaidGrantWorker.perform(job(%{"invoice_id" => "in_1"}))
  end

  test "treats a fully already-granted invoice as done rather than retrying" do
    stub(Prepaid, :grant_for_paid_invoice, fn _invoice -> {:ok, []} end)

    assert :ok = CreateRunnerPrepaidGrantWorker.perform(job(%{"invoice_id" => "in_1"}))
  end

  test "keeps the grant owed by snoozing while no runner price exists" do
    stub(Prepaid, :grant_for_paid_invoice, fn _invoice -> {:error, :no_runner_prices_configured} end)

    assert {:snooze, 3600} = CreateRunnerPrepaidGrantWorker.perform(job(%{"invoice_id" => "in_1"}, 1))
    assert {:snooze, 3600} = CreateRunnerPrepaidGrantWorker.perform(job(%{"invoice_id" => "in_1"}, 72))
  end

  test "stops snoozing and surfaces the misconfiguration once a human is needed" do
    stub(Prepaid, :grant_for_paid_invoice, fn _invoice -> {:error, :no_runner_prices_configured} end)

    assert {:error, :no_runner_prices_configured} =
             CreateRunnerPrepaidGrantWorker.perform(job(%{"invoice_id" => "in_1"}, 73))
  end

  test "lets any other failure retry" do
    stub(Prepaid, :grant_for_paid_invoice, fn _invoice -> {:error, {:invalid_metadata, :funding_ratio_bp, "1250"}} end)

    assert {:error, {:invalid_metadata, :funding_ratio_bp, "1250"}} =
             CreateRunnerPrepaidGrantWorker.perform(job(%{"invoice_id" => "in_1"}))
  end

  test "retries when the invoice cannot be read back" do
    stub(Stripe.Invoice, :retrieve, fn _invoice_id -> {:error, :timeout} end)
    reject(&Prepaid.grant_for_paid_invoice/1)

    assert {:error, :timeout} = CreateRunnerPrepaidGrantWorker.perform(job(%{"invoice_id" => "in_1"}))
  end

  test "is unique on the invoice, so a redelivered webhook cannot enqueue a second grant" do
    assert {:ok, first} = Oban.insert(CreateRunnerPrepaidGrantWorker.new(%{invoice_id: "in_unique"}))
    assert {:ok, second} = Oban.insert(CreateRunnerPrepaidGrantWorker.new(%{invoice_id: "in_unique"}))

    assert second.id == first.id
    assert second.conflict?
  end
end

defmodule Atlas.Finance.SyncTest do
  use Atlas.DataCase, async: true
  use Mimic

  alias Atlas.Audit.Activity
  alias Atlas.Finance.Account
  alias Atlas.Finance.PaymentDetection
  alias Atlas.Finance.Providers.Qonto
  alias Atlas.Finance.Source
  alias Atlas.Finance.Sync
  alias Atlas.Finance.SyncRun
  alias Atlas.Finance.Transaction
  alias Atlas.MCP.ToolCase
  alias Atlas.Repo

  setup :verify_on_exit!

  test "syncs source metadata, accounts, transactions, and sync runs" do
    reject(&PaymentDetection.review_and_notify/1)

    now = ~U[2026-05-26 09:00:00Z]
    company = ToolCase.insert_account!(%{name: "Tuist GmbH", segment: :customer})

    finance_config = [
      sources: [
        %{
          key: "demo-qonto",
          provider: :qonto,
          name: "Demo Qonto",
          atlas_account_key: company.account_key
        }
      ]
    ]

    expect(Qonto, :describe_source, fn source_config ->
      {:ok,
       %{
         external_id: "source:#{source_config.key}",
         name: source_config.name,
         metadata: %{"provider" => "fake_finance_provider"}
       }}
    end)

    expect(Qonto, :list_accounts, fn _source_config ->
      {:ok,
       [
         %{
           external_id: "acct_operating",
           name: "Operating Account",
           account_type: "checking",
           currency: "EUR",
           main: true,
           status: "active",
           balance_value: Decimal.new("1000.00"),
           balance_currency: "EUR",
           available_balance_value: Decimal.new("900.00"),
           available_balance_currency: "EUR",
           metadata: %{"seed" => "fake"}
         }
       ]}
    end)

    expect(Qonto, :list_transactions, fn _source_config, account, opts ->
      now = Keyword.fetch!(opts, :now)

      transactions =
        case account.external_id do
          "acct_operating" ->
            [
              %{
                external_id: "txn_payroll",
                status: "completed",
                direction: "debit",
                kind: "salary",
                counterparty_name: "Payroll Provider",
                description: "May payroll",
                reference: "PAYROLL-MAY",
                amount_value: Decimal.new("100.00"),
                amount_currency: "EUR",
                booked_at: now,
                settled_at: now,
                provider_updated_at: now,
                metadata: %{"batch" => "may"},
                raw: %{"external_account_id" => account.external_id}
              }
            ]

          _other ->
            []
        end

      {:ok, %{transactions: transactions, next_cursor: now}}
    end)

    assert {:ok, %{accounts_seen: 1, transactions_seen: 1}} =
             Sync.run_source("demo-qonto", now: now, finance_config: finance_config)

    source = Repo.get_by!(Source, config_key: "demo-qonto")
    account = Repo.get_by!(Account, finance_source_id: source.id, external_id: "acct_operating")

    transaction =
      Repo.get_by!(Transaction, finance_account_id: account.id, external_id: "txn_payroll")

    sync_run = Repo.one!(from sync_run in SyncRun, where: sync_run.finance_source_id == ^source.id)

    assert source.provider == "qonto"
    assert source.atlas_account_id == company.id
    assert source.external_id == "source:demo-qonto"
    assert source.last_successful_sync_at == now
    assert account.name == "Operating Account"
    assert account.transactions_synced_at == now
    assert transaction.counterparty_name == "Payroll Provider"
    assert transaction.amount_currency == "EUR"
    assert sync_run.status == "ok"
    assert sync_run.accounts_seen == 1
    assert sync_run.transactions_seen == 1

    activity = Repo.get_by!(Activity, action: "finance_source.synced", target_id: source.id)
    assert activity.metadata["transactions_seen"] == 1
  end

  test "records safe metadata when a source sync fails" do
    finance_config = [
      sources: [
        %{
          key: "failed-qonto",
          provider: :qonto,
          name: "Failed Qonto"
        }
      ]
    ]

    expect(Qonto, :describe_source, fn _source_config ->
      {:error, {:http, 422, %{"account_number" => "sensitive-account-number", "error" => "invalid"}}}
    end)

    assert {:error, {:http, 422, _body}} =
             Sync.run_source("failed-qonto", finance_config: finance_config)

    activity = Repo.get_by!(Activity, action: "finance_source.sync_failed", target_label: "failed-qonto")
    assert activity.metadata["error_type"] == "http"
    assert activity.metadata["status"] == 422
    refute Map.has_key?(activity.metadata, "reason")
    refute inspect(activity.metadata) =~ "sensitive-account-number"
  end

  test "flags transfers from our own legal entities as non-runway" do
    reject(&PaymentDetection.review_and_notify/1)

    now = ~U[2026-05-26 09:00:00Z]
    company = ToolCase.insert_account!(%{name: "Tuist GmbH", segment: :customer})

    finance_config = [
      internal_entity_names: ["Tuist GmbH", "Tuist Inc."],
      sources: [
        %{key: "demo-qonto", provider: :qonto, name: "Demo Qonto", atlas_account_key: company.account_key}
      ]
    ]

    expect(Qonto, :describe_source, fn source_config ->
      {:ok, %{external_id: "source:#{source_config.key}", name: source_config.name, metadata: %{}}}
    end)

    expect(Qonto, :list_accounts, fn _source_config ->
      {:ok,
       [
         %{
           external_id: "acct_operating",
           name: "Operating",
           account_type: "checking",
           currency: "EUR",
           main: true,
           status: "active",
           balance_value: Decimal.new("1000.00"),
           balance_currency: "EUR",
           available_balance_value: Decimal.new("1000.00"),
           available_balance_currency: "EUR",
           metadata: %{}
         }
       ]}
    end)

    expect(Qonto, :list_transactions, fn _source_config, _account, opts ->
      now = Keyword.fetch!(opts, :now)

      transactions = [
        # Intercompany wire booked as ordinary income — provider did not tag it.
        %{
          external_id: "txn_intercompany",
          status: "completed",
          direction: "credit",
          kind: "income",
          counterparty_name: "Tuist GmbH",
          amount_value: Decimal.new("20000.00"),
          amount_currency: "EUR",
          booked_at: now,
          settled_at: now,
          provider_updated_at: now,
          affects_cash_balance: true,
          affects_runway: true,
          metadata: %{},
          raw: %{}
        },
        # Intercompany SWIFT credit where the bank appended the address; the
        # counterparty must still resolve to our entity via prefix matching.
        %{
          external_id: "txn_intercompany_address",
          status: "completed",
          direction: "credit",
          kind: "swift_income",
          counterparty_name: "Tuist Inc.\n, 1111B S Governors Ave",
          amount_value: Decimal.new("256000.00"),
          amount_currency: "EUR",
          booked_at: now,
          settled_at: now,
          provider_updated_at: now,
          affects_cash_balance: true,
          affects_runway: true,
          metadata: %{},
          raw: %{}
        },
        # A genuine customer payment.
        %{
          external_id: "txn_customer",
          status: "completed",
          direction: "credit",
          kind: "income",
          counterparty_name: "Acme Ltd",
          amount_value: Decimal.new("5000.00"),
          amount_currency: "EUR",
          booked_at: now,
          settled_at: now,
          provider_updated_at: now,
          affects_cash_balance: true,
          affects_runway: true,
          metadata: %{},
          raw: %{}
        }
      ]

      {:ok, %{transactions: transactions, next_cursor: now}}
    end)

    assert {:ok, _summary} = Sync.run_source("demo-qonto", now: now, finance_config: finance_config)

    intercompany = Repo.get_by!(Transaction, external_id: "txn_intercompany")
    intercompany_address = Repo.get_by!(Transaction, external_id: "txn_intercompany_address")
    customer = Repo.get_by!(Transaction, external_id: "txn_customer")

    # The intercompany transfer still affects cash, but not runway/burn.
    assert intercompany.affects_cash_balance
    refute intercompany.affects_runway

    # The address-suffixed intercompany wire is matched by prefix and excluded.
    assert intercompany_address.affects_cash_balance
    refute intercompany_address.affects_runway

    # The real customer payment is untouched.
    assert customer.affects_runway
  end

  test "reviews a newly inserted transaction after the source has completed its initial import" do
    previous_sync_at = ~U[2026-07-15 08:00:00Z]
    now = ~U[2026-07-15 09:00:00Z]
    company = ToolCase.insert_account!(%{name: "Tuist Inc.", segment: :customer})

    %Source{}
    |> Source.changeset(%{
      atlas_account_id: company.id,
      provider: "qonto",
      config_key: "payment-qonto",
      name: "Payment Qonto",
      last_successful_sync_at: previous_sync_at
    })
    |> Repo.insert!()

    finance_config = [
      sources: [
        %{
          key: "payment-qonto",
          provider: :qonto,
          name: "Payment Qonto",
          atlas_account_key: company.account_key
        }
      ]
    ]

    expect(Qonto, :describe_source, fn source_config ->
      {:ok, %{external_id: "source:#{source_config.key}", name: source_config.name, metadata: %{}}}
    end)

    expect(Qonto, :list_accounts, fn _source_config ->
      {:ok,
       [
         %{
           external_id: "acct_operating",
           name: "Operating",
           account_type: "checking",
           currency: "EUR",
           main: true,
           status: "active",
           balance_value: Decimal.new("1000.00"),
           balance_currency: "EUR",
           available_balance_value: Decimal.new("1000.00"),
           available_balance_currency: "EUR",
           metadata: %{}
         }
       ]}
    end)

    expect(Qonto, :list_transactions, fn _source_config, _account, opts ->
      assert Keyword.fetch!(opts, :synced_after) == DateTime.add(now, -365, :day)

      {:ok,
       %{
         transactions: [
           %{
             external_id: "txn_new_customer_payment",
             status: "completed",
             direction: "credit",
             kind: "income",
             counterparty_name: "Acme International Ltd",
             amount_value: Decimal.new("30000.00"),
             amount_currency: "EUR",
             booked_at: now,
             settled_at: now,
             provider_updated_at: now,
             affects_cash_balance: true,
             affects_runway: true,
             metadata: %{},
             raw: %{}
           }
         ],
         next_cursor: now
       }}
    end)

    expect(PaymentDetection, :review_and_notify, fn transaction ->
      assert transaction.external_id == "txn_new_customer_payment"
      assert transaction.direction == "credit"
      {:ok, "notified"}
    end)

    assert {:ok, %{transactions_seen: 1}} =
             Sync.run_source("payment-qonto", now: now, finance_config: finance_config)
  end
end

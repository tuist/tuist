defmodule Atlas.Finance.Sync do
  @moduledoc false

  import Ecto.Query

  alias Atlas.Accounts.Account, as: AtlasAccount
  alias Atlas.Audit
  alias Atlas.Finance.Account
  alias Atlas.Finance.Config
  alias Atlas.Finance.PaymentDetection
  alias Atlas.Finance.Providers.Helpers
  alias Atlas.Finance.Providers.Mercury
  alias Atlas.Finance.Providers.Qonto
  alias Atlas.Finance.Source
  alias Atlas.Finance.SyncRun
  alias Atlas.Finance.Transaction
  alias Atlas.Repo

  require Logger

  @account_upsert_fields [
    :provider,
    :name,
    :account_type,
    :account_subtype,
    :currency,
    :iban,
    :bic,
    :main,
    :status,
    :balance_value,
    :balance_currency,
    :available_balance_value,
    :available_balance_currency,
    :transactions_synced_at,
    :refreshed_at,
    :metadata,
    :updated_at
  ]
  @transaction_upsert_fields [
    :provider,
    :status,
    :direction,
    :kind,
    :counterparty_name,
    :description,
    :reference,
    :amount_value,
    :amount_currency,
    :local_amount_value,
    :local_amount_currency,
    :fee_value,
    :fee_currency,
    :running_balance_value,
    :running_balance_currency,
    :booked_at,
    :settled_at,
    :provider_updated_at,
    :affects_cash_balance,
    :affects_runway,
    :metadata,
    :raw
  ]

  def run_source(source_key, opts \\ []) when is_binary(source_key) do
    now =
      opts
      |> Keyword.get(:now, DateTime.utc_now())
      |> Helpers.datetime()

    result =
      with {:ok, source_config} <- fetch_source_config(source_key, opts),
           {:ok, provider} <- provider_module(source_config.provider),
           {:ok, source} <- ensure_source(source_config),
           notify_new_payments? = not is_nil(source.last_successful_sync_at),
           {:ok, sync_run} <- start_sync_run(source, now),
           {:ok, source} <- refresh_source(source, source_config, provider),
           {:ok, accounts} <- provider.list_accounts(source_config),
           internal_names = internal_entity_names(opts),
           {:ok, summary} <-
             sync_accounts(source, accounts, source_config, provider, now, internal_names, notify_new_payments?),
           {:ok, _source} <- mark_source_synced(source, now),
           {:ok, _sync_run} <- finish_sync_run(sync_run, summary, now) do
        {:ok, Map.put(summary, :source_id, source.id)}
      end

    case result do
      {:ok, summary} = success ->
        audit_sync_completed(source_key, summary)
        success

      {:error, :source_not_configured} = error ->
        error

      {:error, reason} = error ->
        Logger.warning("Finance sync failed for #{source_key}: #{inspect(reason)}")
        maybe_mark_failed(source_key, now, reason)
        audit_sync_failed(source_key, reason)
        error
    end
  end

  defp fetch_source_config(source_key, opts) do
    case Keyword.fetch(opts, :finance_config) do
      {:ok, finance_config} -> Config.fetch_source(source_key, finance_config)
      :error -> Config.fetch_source(source_key)
    end
  end

  defp provider_module(provider_key) do
    case default_provider(provider_key) do
      nil -> {:error, {:unsupported_provider, provider_key}}
      provider -> {:ok, provider}
    end
  end

  defp default_provider(:qonto), do: Qonto
  defp default_provider(:mercury), do: Mercury
  defp default_provider(_provider), do: nil

  defp ensure_source(source_config) do
    with {:ok, atlas_account_id} <- resolve_atlas_account_id(source_config) do
      attrs = %{
        atlas_account_id: atlas_account_id,
        provider: to_string(source_config.provider),
        config_key: source_config.key,
        name: source_config.name
      }

      %Source{}
      |> Source.changeset(attrs)
      |> Repo.insert(
        on_conflict: {:replace, [:atlas_account_id, :provider, :name, :updated_at]},
        conflict_target: [:config_key],
        returning: true
      )
    end
  end

  defp refresh_source(source, source_config, provider) do
    with {:ok, atlas_account_id} <- resolve_atlas_account_id(source_config),
         {:ok, attrs} <- provider.describe_source(source_config) do
      source
      |> Source.changeset(%{
        atlas_account_id: atlas_account_id,
        provider: to_string(source_config.provider),
        name: attrs[:name] || source_config.name,
        external_id: attrs[:external_id],
        metadata: attrs[:metadata] || %{}
      })
      |> Repo.update()
    end
  end

  defp resolve_atlas_account_id(source_config) do
    account_key = Helpers.presence(source_config[:atlas_account_key])
    account_name = Helpers.presence(source_config[:atlas_account_name])

    cond do
      is_binary(account_key) ->
        case get_atlas_account_by_key(account_key) do
          {:ok, account} -> {:ok, account.id}
          {:error, :not_found} -> {:error, {:atlas_account_not_found, {:account_key, account_key}}}
        end

      is_binary(account_name) ->
        case get_atlas_account_by_name(account_name) do
          {:ok, account} -> {:ok, account.id}
          {:error, :not_found} -> {:error, {:atlas_account_not_found, {:account_name, account_name}}}
        end

      true ->
        {:ok, nil}
    end
  end

  defp get_atlas_account_by_key(account_key) when is_binary(account_key) do
    AtlasAccount
    |> where([account], account.account_key == ^String.trim(account_key))
    |> order_by([account], asc: account.inserted_at)
    |> limit(1)
    |> Repo.one()
    |> to_atlas_account_result()
  end

  defp get_atlas_account_by_name(account_name) when is_binary(account_name) do
    AtlasAccount
    |> where([account], fragment("lower(?) = ?", account.name, ^String.downcase(account_name)))
    |> order_by([account], asc: account.inserted_at)
    |> limit(1)
    |> Repo.one()
    |> to_atlas_account_result()
  end

  defp to_atlas_account_result(nil), do: {:error, :not_found}
  defp to_atlas_account_result(%AtlasAccount{} = account), do: {:ok, account}

  defp start_sync_run(source, now) do
    %SyncRun{}
    |> SyncRun.changeset(%{
      finance_source_id: source.id,
      status: "running",
      started_at: now,
      metadata: %{"config_key" => source.config_key}
    })
    |> Repo.insert()
  end

  defp sync_accounts(source, accounts, source_config, provider, now, internal_names, notify_new_payments?) do
    Enum.reduce_while(accounts, {:ok, %{accounts_seen: 0, transactions_seen: 0}}, fn account_attrs, {:ok, summary} ->
      with {:ok, account} <- upsert_account(source, account_attrs, now),
           sync_start = sync_start(account, now),
           {:ok, %{transactions: transactions, next_cursor: next_cursor}} <-
             provider.list_transactions(source_config, account, synced_after: sync_start, now: now),
           {:ok, _count} <-
             upsert_transactions(account, transactions, internal_names, notify_new_payments?),
           {:ok, _account} <- update_account_sync_cursor(account, next_cursor, now) do
        {:cont,
         {:ok,
          %{
            accounts_seen: summary.accounts_seen + 1,
            transactions_seen: summary.transactions_seen + length(transactions)
          }}}
      else
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  end

  defp upsert_account(source, account_attrs, now) do
    attrs =
      account_attrs
      |> Map.merge(%{
        finance_source_id: source.id,
        provider: source.provider,
        refreshed_at: now
      })

    %Account{}
    |> Account.changeset(attrs)
    |> Repo.insert(
      on_conflict: {:replace, @account_upsert_fields},
      conflict_target: [:finance_source_id, :external_id],
      returning: true
    )
  end

  defp upsert_transactions(account, transactions, internal_names, notify_new_payments?) do
    count =
      Enum.reduce_while(transactions, 0, fn transaction_attrs, count ->
        attrs =
          transaction_attrs
          |> Map.put(:finance_account_id, account.id)
          |> Map.put(:provider, account.provider)
          |> flag_internal_transfer(internal_names)

        case upsert_transaction(attrs) do
          {:ok, transaction, new?} ->
            maybe_review_new_payment(transaction, new?, notify_new_payments?)
            {:cont, count + 1}

          {:error, reason} ->
            {:halt, {:error, reason}}
        end
      end)

    case count do
      {:error, reason} -> {:error, reason}
      value -> {:ok, value}
    end
  end

  defp upsert_transaction(attrs) do
    new? =
      not Repo.exists?(
        from(transaction in Transaction,
          where:
            transaction.finance_account_id == ^attrs.finance_account_id and
              transaction.external_id == ^attrs.external_id
        )
      )

    %Transaction{}
    |> Transaction.changeset(attrs)
    |> Repo.insert(
      on_conflict: {:replace, @transaction_upsert_fields},
      conflict_target: [:finance_account_id, :external_id],
      returning: true
    )
    |> case do
      {:ok, transaction} -> {:ok, transaction, new?}
      {:error, reason} -> {:error, reason}
    end
  end

  defp maybe_review_new_payment(transaction, true, true) do
    _result = PaymentDetection.review_and_notify(transaction)
    :ok
  end

  defp maybe_review_new_payment(_transaction, _new?, _notify_new_payments?), do: :ok

  # Transactions whose counterparty is one of our own legal entities are
  # intercompany transfers, not operating revenue/expense. Providers don't
  # always tag these (Qonto books cross-entity wires as "income"), so exclude
  # them from runway/burn while keeping them on the cash balance.
  defp flag_internal_transfer(attrs, internal_names) do
    if Config.internal_counterparty?(Map.get(attrs, :counterparty_name), internal_names) do
      Map.put(attrs, :affects_runway, false)
    else
      attrs
    end
  end

  # The normalized list of our own legal-entity names (configured), used to
  # recognize intercompany transfers by counterparty.
  defp internal_entity_names(opts) do
    opts
    |> finance_config()
    |> Config.normalized_internal_entity_names()
  end

  defp finance_config(opts) do
    Keyword.get(opts, :finance_config) || Application.get_env(:atlas, :finance, [])
  end

  defp update_account_sync_cursor(account, next_cursor, now) do
    account
    |> Account.changeset(%{
      transactions_synced_at: next_cursor || now,
      refreshed_at: now
    })
    |> Repo.update()
  end

  defp sync_start(%Account{transactions_synced_at: nil}, now) do
    DateTime.add(now, -Config.initial_lookback_days() * 24 * 60 * 60, :second)
  end

  defp sync_start(%Account{transactions_synced_at: %DateTime{} = synced_at}, _now) do
    DateTime.add(synced_at, -Config.sync_overlap_seconds(), :second)
  end

  defp mark_source_synced(source, now) do
    source
    |> Source.changeset(%{
      last_synced_at: now,
      last_successful_sync_at: now,
      last_error: nil
    })
    |> Repo.update()
  end

  defp finish_sync_run(sync_run, summary, now) do
    sync_run
    |> SyncRun.changeset(%{
      status: "ok",
      finished_at: now,
      accounts_seen: summary.accounts_seen,
      transactions_seen: summary.transactions_seen
    })
    |> Repo.update()
  end

  defp maybe_mark_failed(source_key, now, reason) do
    case Repo.get_by(Source, config_key: source_key) do
      nil ->
        :ok

      source ->
        with {:ok, _source} <- mark_source_failed(source, now, reason),
             %SyncRun{} = sync_run <- latest_running_sync_run(source.id),
             {:ok, _sync_run} <- fail_sync_run(sync_run, reason, now) do
          :ok
        else
          _error -> :ok
        end
    end
  end

  defp mark_source_failed(source, now, reason) do
    source
    |> Source.changeset(%{
      last_synced_at: now,
      last_error: format_error(reason)
    })
    |> Repo.update()
  end

  defp latest_running_sync_run(source_id) do
    SyncRun
    |> where([sync_run], sync_run.finance_source_id == ^source_id and sync_run.status == "running")
    |> order_by([sync_run], desc: sync_run.inserted_at)
    |> limit(1)
    |> Repo.one()
  end

  defp fail_sync_run(sync_run, reason, now) do
    sync_run
    |> SyncRun.changeset(%{
      status: "error",
      finished_at: now,
      error: format_error(reason)
    })
    |> Repo.update()
  end

  defp format_error(%Ecto.Changeset{} = changeset) do
    changeset
    |> Ecto.Changeset.traverse_errors(fn {message, opts} ->
      Enum.reduce(opts, message, fn {key, value}, acc ->
        String.replace(acc, "%{#{key}}", to_string(value))
      end)
    end)
    |> inspect()
  end

  defp format_error({:atlas_account_not_found, {:account_key, account_key}}) do
    "atlas account not found for account_key #{inspect(account_key)}"
  end

  defp format_error({:atlas_account_not_found, {:account_name, account_name}}) do
    "atlas account not found for name #{inspect(account_name)}"
  end

  defp format_error({:http, status, _body}), do: "http #{status}: provider response omitted"
  defp format_error({:unsupported_provider, provider}), do: "unsupported provider #{inspect(provider)}"
  defp format_error(other), do: inspect(other)

  defp audit_sync_completed(source_key, summary) do
    Audit.record(
      "finance_source.synced",
      %{
        target_type: "finance_source",
        target_id: summary.source_id,
        target_label: source_key,
        metadata: %{
          "path" => "/finance",
          "source_key" => source_key,
          "accounts_seen" => summary.accounts_seen,
          "transactions_seen" => summary.transactions_seen
        }
      },
      interface: "worker"
    )
  end

  defp audit_sync_failed(source_key, reason) do
    Audit.record(
      "finance_source.sync_failed",
      %{
        target_type: "finance_source",
        target_label: source_key,
        metadata:
          Map.merge(
            %{
              "path" => "/finance",
              "source_key" => source_key
            },
            audit_failure_metadata(reason)
          )
      },
      interface: "worker"
    )
  end

  defp audit_failure_metadata({:http, status, _body}) when is_integer(status) do
    %{"error_type" => "http", "status" => status}
  end

  defp audit_failure_metadata({:unsupported_provider, _provider}), do: %{"error_type" => "unsupported_provider"}

  defp audit_failure_metadata({:atlas_account_not_found, {field, _value}})
       when field in [:account_key, :account_name] do
    %{"error_type" => "atlas_account_not_found", "match_field" => Atom.to_string(field)}
  end

  defp audit_failure_metadata(%Ecto.Changeset{}), do: %{"error_type" => "validation_failed"}

  defp audit_failure_metadata(reason) when is_atom(reason), do: %{"error_type" => Atom.to_string(reason)}

  defp audit_failure_metadata(_reason), do: %{"error_type" => "sync_failed"}
end

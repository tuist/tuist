defmodule Atlas.Finance.QontoInvoiceBackfill do
  @moduledoc false

  import Ecto.Query

  alias Atlas.Accounts.Account, as: AtlasAccount
  alias Atlas.Audit
  alias Atlas.Documents
  alias Atlas.Finance.Account
  alias Atlas.Finance.Config
  alias Atlas.Finance.Providers.Helpers
  alias Atlas.Finance.Providers.Qonto
  alias Atlas.Finance.Source
  alias Atlas.Finance.Transaction
  alias Atlas.Repo

  require Logger

  @default_batch_size 100
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

  def run(opts \\ []) do
    batch_size = Keyword.get(opts, :batch_size, @default_batch_size)
    max_transactions = Keyword.get(opts, :max_transactions, :infinity)
    now = opts |> Keyword.get(:now, DateTime.utc_now()) |> Helpers.datetime()

    with {:ok, source_config} <- fetch_qonto_source_config(opts),
         {:ok, sync_summary} <- maybe_sync_historical_transactions(source_config, opts, now) do
      summary =
        empty_summary()
        |> Map.merge(sync_summary)
        |> then(&drain_batches(source_config, opts, batch_size, max_transactions, &1))

      summary = %{summary | errors: Enum.reverse(summary.errors)}
      audit_backfill(summary, opts)
      {:ok, summary}
    end
  end

  defp empty_summary do
    %{
      accounts_seen: 0,
      transactions_synced: 0,
      transactions_seen: 0,
      attachments_seen: 0,
      documents_imported: 0,
      skipped: 0,
      errors: []
    }
  end

  defp maybe_sync_historical_transactions(source_config, opts, now) do
    if Keyword.get(opts, :sync_historical_transactions?, true),
      do: sync_historical_transactions(source_config, opts, now),
      else: {:ok, %{accounts_seen: 0, transactions_synced: 0}}
  end

  defp sync_historical_transactions(source_config, opts, now) do
    provider = Keyword.get(opts, :provider, Qonto)

    with {:ok, source} <- ensure_source(source_config),
         {:ok, account_attrs} <- provider.list_accounts(source_config) do
      internal_names = internal_entity_names(opts)

      Enum.reduce_while(account_attrs, {:ok, %{accounts_seen: 0, transactions_synced: 0}}, fn attrs, {:ok, summary} ->
        with {:ok, account} <- upsert_account(source, attrs, now),
             {:ok, %{transactions: transactions}} <-
               provider.list_transactions(source_config, account, synced_after: nil, now: now),
             {:ok, transaction_count} <- upsert_transactions(account, transactions, internal_names) do
          {:cont,
           {:ok,
            %{
              accounts_seen: summary.accounts_seen + 1,
              transactions_synced: summary.transactions_synced + transaction_count
            }}}
        else
          {:error, reason} -> {:halt, {:error, reason}}
        end
      end)
    end
  end

  defp ensure_source(source_config) do
    existing_source = Repo.get_by(Source, config_key: source_config.key)

    attrs = %{
      atlas_account_id:
        resolve_atlas_account_id(source_config) || (existing_source && existing_source.atlas_account_id),
      provider: to_string(source_config.provider),
      config_key: source_config.key,
      name: source_config.name
    }

    case existing_source do
      %Source{} = source ->
        source
        |> Source.changeset(attrs)
        |> Repo.update()

      nil ->
        %Source{}
        |> Source.changeset(attrs)
        |> Repo.insert()
    end
  end

  defp resolve_atlas_account_id(source_config) do
    account_key = Helpers.presence(source_config[:atlas_account_key])
    account_name = Helpers.presence(source_config[:atlas_account_name])

    cond do
      is_binary(account_key) ->
        AtlasAccount
        |> where([account], account.account_key == ^account_key)
        |> order_by([account], asc: account.inserted_at)
        |> limit(1)
        |> Repo.one()
        |> then(&(&1 && &1.id))

      is_binary(account_name) ->
        AtlasAccount
        |> where([account], fragment("lower(?) = ?", account.name, ^String.downcase(account_name)))
        |> order_by([account], asc: account.inserted_at)
        |> limit(1)
        |> Repo.one()
        |> then(&(&1 && &1.id))

      true ->
        nil
    end
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

  defp upsert_transactions(account, transactions, internal_names) do
    count =
      Enum.reduce_while(transactions, 0, fn transaction_attrs, count ->
        attrs =
          transaction_attrs
          |> Map.put(:finance_account_id, account.id)
          |> Map.put(:provider, account.provider)
          |> flag_internal_transfer(internal_names)
          |> preserve_backfill_metadata()

        case upsert_transaction(attrs) do
          {:ok, _transaction} -> {:cont, count + 1}
          {:error, reason} -> {:halt, {:error, reason}}
        end
      end)

    case count do
      {:error, reason} -> {:error, reason}
      value -> {:ok, value}
    end
  end

  defp upsert_transaction(attrs) do
    %Transaction{}
    |> Transaction.changeset(attrs)
    |> Repo.insert(
      on_conflict: {:replace, @transaction_upsert_fields},
      conflict_target: [:finance_account_id, :external_id],
      returning: true
    )
  end

  defp flag_internal_transfer(attrs, internal_names) do
    if Config.internal_counterparty?(Map.get(attrs, :counterparty_name), internal_names) do
      Map.put(attrs, :affects_runway, false)
    else
      attrs
    end
  end

  defp preserve_backfill_metadata(attrs) do
    existing_metadata =
      Transaction
      |> where([transaction], transaction.finance_account_id == ^attrs.finance_account_id)
      |> where([transaction], transaction.external_id == ^attrs.external_id)
      |> select([transaction], transaction.metadata)
      |> Repo.one()
      |> Kernel.||(%{})
      |> Map.take(["qonto_invoice_backfilled", "qonto_invoice_backfilled_at"])

    metadata =
      attrs
      |> Map.get(:metadata, %{})
      |> Kernel.||(%{})
      |> Map.merge(existing_metadata)

    Map.put(attrs, :metadata, metadata)
  end

  defp internal_entity_names(opts) do
    opts
    |> finance_config()
    |> Config.normalized_internal_entity_names()
  end

  defp finance_config(opts) do
    Keyword.get(opts, :finance_config) || Application.get_env(:atlas, :finance, [])
  end

  defp drain_batches(_source_config, _opts, _batch_size, max_transactions, summary)
       when is_integer(max_transactions) and summary.transactions_seen >= max_transactions do
    summary
  end

  defp drain_batches(source_config, opts, batch_size, max_transactions, summary) do
    remaining = remaining_limit(max_transactions, summary.transactions_seen, batch_size)
    transactions = candidate_transactions(source_config.key, remaining)

    case transactions do
      [] ->
        summary

      _transactions ->
        summary = Enum.reduce(transactions, summary, &import_transaction(source_config, opts, &1, &2))
        maybe_continue_batches(source_config, opts, batch_size, max_transactions, summary)
    end
  end

  defp maybe_continue_batches(_source_config, _opts, _batch_size, _max_transactions, %{errors: [_ | _]} = summary) do
    summary
  end

  defp maybe_continue_batches(source_config, opts, batch_size, max_transactions, summary) do
    drain_batches(source_config, opts, batch_size, max_transactions, summary)
  end

  defp remaining_limit(:infinity, _seen, batch_size), do: batch_size
  defp remaining_limit(max_transactions, seen, batch_size), do: min(batch_size, max(max_transactions - seen, 0))

  defp import_transaction(source_config, opts, transaction, summary) do
    case import_transaction_attachments(source_config, transaction, opts) do
      {:ok, result} ->
        mark_transaction_backfilled(transaction)

        %{
          summary
          | transactions_seen: summary.transactions_seen + 1,
            attachments_seen: summary.attachments_seen + result.attachments_seen,
            documents_imported: summary.documents_imported + result.documents_imported,
            skipped: summary.skipped + result.skipped
        }

      {:error, reason} ->
        Logger.warning("Qonto invoice backfill failed for transaction #{transaction.id}: #{inspect(reason)}")

        %{
          summary
          | transactions_seen: summary.transactions_seen + 1,
            errors: [%{transaction_id: transaction.id, reason: inspect(reason)} | summary.errors]
        }
    end
  end

  defp fetch_qonto_source_config(opts) do
    source_key = Keyword.get(opts, :source_key)
    finance_config = Keyword.get(opts, :finance_config)

    if is_binary(source_key) and source_key != "" do
      if finance_config, do: Config.fetch_source(source_key, finance_config), else: Config.fetch_source(source_key)
    else
      sources =
        if finance_config do
          Config.configured_sources(finance_config)
        else
          Config.configured_sources()
        end

      case Enum.find(sources, &(&1.provider == :qonto)) do
        nil -> {:error, :qonto_source_not_configured}
        source -> {:ok, source}
      end
    end
  end

  defp candidate_transactions(source_key, limit) do
    from(transaction in Transaction, as: :transaction)
    |> join(:inner, [transaction], account in assoc(transaction, :account), as: :account)
    |> join(:inner, [account: account], source in assoc(account, :source), as: :source)
    |> where([transaction], transaction.provider == "qonto")
    |> where([transaction], transaction.direction == "debit")
    |> where([source: source], source.config_key == ^source_key)
    |> where(
      [transaction],
      fragment("coalesce(?->>'qonto_invoice_backfilled', 'false') != 'true'", transaction.metadata)
    )
    |> where(
      [transaction],
      not exists(
        from invoice in "finance_invoices",
          where: invoice.finance_transaction_id == parent_as(:transaction).id,
          select: 1
      )
    )
    |> preload(account: [source: :atlas_account])
    |> order_by([transaction], desc_nulls_last: transaction.settled_at, desc_nulls_last: transaction.booked_at)
    |> limit(^limit)
    |> Repo.all()
  end

  defp import_transaction_attachments(source_config, %Transaction{} = transaction, opts) do
    provider = Keyword.get(opts, :provider, Qonto)

    with {:ok, attachments} <- provider.list_transaction_attachments(source_config, transaction.external_id) do
      result =
        attachments
        |> Enum.reject(&is_nil/1)
        |> Enum.reduce_while(%{attachments_seen: length(attachments), documents_imported: 0, skipped: 0}, fn attachment,
                                                                                                             acc ->
          import_or_skip_attachment(provider, source_config, transaction, attachment, acc)
        end)

      case result do
        {:error, reason} -> {:error, reason}
        summary -> {:ok, summary}
      end
    end
  end

  defp import_or_skip_attachment(provider, source_config, transaction, attachment, acc) do
    case importable_attachment_id(attachment) do
      {:ok, _attachment_id} -> import_attachment_result(provider, source_config, transaction, attachment, acc)
      :skip -> {:cont, %{acc | skipped: acc.skipped + 1}}
    end
  end

  defp importable_attachment_id(%{"id" => attachment_id}) when is_binary(attachment_id) and attachment_id != "" do
    if Documents.imported_from_qonto_attachment?(attachment_id), do: :skip, else: {:ok, attachment_id}
  end

  defp importable_attachment_id(_attachment), do: :skip

  defp import_attachment_result(provider, source_config, transaction, attachment, acc) do
    case import_attachment(provider, source_config, transaction, attachment) do
      {:ok, _document} -> {:cont, %{acc | documents_imported: acc.documents_imported + 1}}
      {:skip, _reason} -> {:cont, %{acc | skipped: acc.skipped + 1}}
      {:error, reason} -> {:halt, {:error, reason}}
    end
  end

  defp import_attachment(provider, source_config, %Transaction{} = transaction, attachment) do
    with {:ok, download} <- provider.download_attachment(source_config, attachment),
         :ok <- ensure_new_attachment_file(download) do
      Documents.create_from_binary(download.body, document_attrs(source_config, transaction, attachment, download))
    end
  end

  defp ensure_new_attachment_file(%{body: body}) when is_binary(body) do
    checksum = :crypto.hash(:sha256, body) |> Base.encode16(case: :lower)

    if Documents.imported_file_checksum?(checksum) do
      {:skip, :duplicate_file}
    else
      :ok
    end
  end

  defp mark_transaction_backfilled(%Transaction{} = transaction) do
    metadata =
      (transaction.metadata || %{})
      |> Map.put("qonto_invoice_backfilled", true)
      |> Map.put(
        "qonto_invoice_backfilled_at",
        DateTime.utc_now() |> DateTime.truncate(:second) |> DateTime.to_iso8601()
      )

    transaction
    |> Transaction.changeset(%{metadata: metadata})
    |> Repo.update()
  end

  defp document_attrs(source_config, %Transaction{} = transaction, attachment, download) do
    attachment_id = attachment["id"] || get_in(download.attachment, ["id"])
    filename = download.filename || "#{transaction.external_id}-attachment"

    %{
      "title" => "Qonto invoice #{transaction.counterparty_name || transaction.reference || transaction.external_id}",
      "original_filename" => filename,
      "content_type" => download.content_type,
      "source" => "qonto",
      "document_date" => transaction_date(transaction),
      "attributes" => %{
        "document_type" => "invoice",
        "finance_transaction_id" => transaction.id,
        "qonto_source_key" => source_config.key,
        "qonto_transaction_id" => transaction.external_id,
        "qonto_attachment_id" => attachment_id,
        "qonto_attachment_probative" => download.probative?,
        "qonto_attachment_file_size" => download.byte_size
      }
    }
  end

  defp transaction_date(%Transaction{} = transaction) do
    transaction
    |> Transaction.occurred_at()
    |> case do
      %DateTime{} = datetime -> DateTime.to_date(datetime)
      _other -> nil
    end
  end

  defp audit_backfill(summary, opts) do
    Audit.record(
      "finance_invoice.qonto_backfill",
      %{
        target_type: "finance_invoice",
        target_label: "Qonto invoice backfill",
        metadata: Map.merge(%{"path" => "/commercial/finance"}, stringify_summary(summary))
      },
      opts
    )
  end

  defp stringify_summary(summary) do
    summary
    |> Map.from_struct()
  rescue
    _ -> Map.new(summary)
  end
end

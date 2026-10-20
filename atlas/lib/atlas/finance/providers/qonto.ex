defmodule Atlas.Finance.Providers.Qonto do
  @moduledoc false

  alias Atlas.Finance.Account
  alias Atlas.Finance.Providers.Helpers

  require Logger

  @base_url "https://thirdparty.qonto.com/v2"
  @per_page 100
  @receive_timeout 15_000
  @statuses ~w(completed pending declined)

  def describe_source(config) do
    params =
      if config[:include_external_accounts] do
        [include_external_accounts: true]
      else
        []
      end

    with {:ok, %{"organization" => organization}} <- get(config, "/organization", params) do
      {:ok,
       %{
         external_id: Helpers.presence(organization["id"]),
         name: Helpers.presence(organization["legal_name"]) || config.name,
         metadata:
           Helpers.compact_map(%{
             "slug" => organization["slug"],
             "legal_country" => organization["legal_country"],
             "legal_form" => organization["legal_form"],
             "locale" => organization["locale"]
           })
       }}
    end
  end

  def list_accounts(config) do
    fetch_accounts(config, 1, [])
  end

  def list_transactions(config, %Account{} = account, opts \\ []) do
    synced_after = Keyword.get(opts, :synced_after)

    params =
      [{"bank_account_id", account.external_id}, {"sort_by", "updated_at:asc"}, {"per_page", @per_page}]
      |> maybe_add_datetime_param("updated_at_from", synced_after)
      |> add_status_params()

    with {:ok, transactions} <- fetch_transactions(config, params, 1, []) do
      next_cursor =
        transactions
        |> Enum.map(& &1.provider_updated_at)
        |> Enum.reduce(Keyword.get(opts, :now), &Helpers.max_datetime/2)

      {:ok, %{transactions: transactions, next_cursor: next_cursor}}
    end
  end

  def list_transaction_attachments(config, transaction_external_id, opts \\ [])
      when is_binary(transaction_external_id) do
    per_page = Keyword.get(opts, :per_page, @per_page)
    fetch_transaction_attachments(config, transaction_external_id, per_page, 1, [])
  end

  def download_attachment(config, attachment) when is_map(attachment) do
    with {:ok, attachment} <- ensure_attachment_url(config, attachment),
         {:ok, download} <- attachment_download(attachment),
         {:ok, body} <- download_attachment_url(download.url, config) do
      {:ok, Map.put(download, :body, body)}
    end
  end

  @doc """
  Uploads a file attachment to a Qonto transaction.

  Accepts the raw file body (binary), a filename, and a content type.
  Returns the created attachment map on success.
  """
  def add_attachment(config, transaction_external_id, file_body, filename, content_type)
      when is_binary(transaction_external_id) and is_binary(file_body) and is_binary(filename) and
             is_binary(content_type) do
    path = "/transactions/#{URI.encode(transaction_external_id)}/attachments"

    case post(config, path,
           body: file_body,
           filename: filename,
           content_type: content_type
         ) do
      {:ok, %{body: body}} ->
        {:ok, body}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Deletes an attachment from Qonto by its attachment ID.
  Returns `:ok` on success.
  """
  def delete_attachment(config, attachment_id) when is_binary(attachment_id) do
    path = "/attachments/#{URI.encode(attachment_id)}"

    case delete(config, path) do
      {:ok, _body} -> :ok
      error -> error
    end
  end

  defp fetch_accounts(config, page, accounts) do
    case get(config, "/bank_accounts", page: page, per_page: @per_page) do
      {:ok, %{"bank_accounts" => fetched_accounts} = body} when is_list(fetched_accounts) ->
        accounts = accounts ++ Enum.map(fetched_accounts, &normalize_account/1)

        case body["meta"] && body["meta"]["next_page"] do
          next_page when is_integer(next_page) -> fetch_accounts(config, next_page, accounts)
          _other -> {:ok, accounts}
        end

      {:ok, other} ->
        {:error, {:invalid_response, other}}

      error ->
        error
    end
  end

  defp fetch_transactions(config, params, page, transactions) do
    case get(config, "/transactions", params ++ [{"page", page}]) do
      {:ok, %{"transactions" => fetched_transactions, "meta" => meta}} when is_list(fetched_transactions) ->
        transactions = transactions ++ Enum.map(fetched_transactions, &normalize_transaction/1)

        case meta["next_page"] do
          next_page when is_integer(next_page) -> fetch_transactions(config, params, next_page, transactions)
          _other -> {:ok, transactions}
        end

      {:ok, other} ->
        {:error, {:invalid_response, other}}

      error ->
        error
    end
  end

  defp fetch_transaction_attachments(config, transaction_external_id, per_page, page, attachments) do
    path = "/transactions/#{URI.encode(transaction_external_id)}/attachments"

    case get(config, path, page: page, per_page: per_page) do
      {:ok, %{"attachments" => fetched_attachments} = body} when is_list(fetched_attachments) ->
        attachments = attachments ++ fetched_attachments

        case body["meta"] && body["meta"]["next_page"] do
          next_page when is_integer(next_page) ->
            fetch_transaction_attachments(config, transaction_external_id, per_page, next_page, attachments)

          _other ->
            {:ok, attachments}
        end

      {:ok, other} ->
        {:error, {:invalid_response, other}}

      error ->
        error
    end
  end

  defp normalize_account(account) do
    currency = account["currency"]
    subtype = if account["is_external_account"] == true, do: "external", else: "business"

    %{
      external_id: Helpers.presence(account["id"]),
      name: Helpers.presence(account["name"]) || Helpers.presence(account["iban"]) || "Qonto account",
      account_type: "bank_account",
      account_subtype: subtype,
      currency: currency,
      iban: Helpers.presence(account["iban"]),
      bic: Helpers.presence(account["bic"]),
      main: account["main"] == true,
      status: Helpers.presence(account["status"]) || "active",
      balance_value: Helpers.decimal(account["balance"]),
      balance_currency: currency,
      available_balance_value: Helpers.decimal(account["authorized_balance"]),
      available_balance_currency: currency,
      metadata:
        Helpers.compact_map(%{
          "organization_id" => account["organization_id"],
          "account_number" => account["account_number"],
          "updated_at" => account["updated_at"],
          "is_external_account" => account["is_external_account"] == true
        })
    }
  end

  defp normalize_transaction(transaction) do
    operation_type = normalize_kind(transaction["operation_type"], transaction["subject_type"])
    status = Helpers.presence(transaction["status"]) || "completed"
    affects_cash_balance = status == "completed"

    %{
      external_id: Helpers.presence(transaction["id"]) || Helpers.presence(transaction["transaction_id"]),
      status: status,
      direction: normalize_direction(transaction["side"]),
      kind: operation_type,
      counterparty_name: Helpers.presence(transaction["label"]),
      description: Helpers.presence(transaction["note"]) || Helpers.presence(transaction["label"]),
      reference: Helpers.presence(transaction["reference"]) || Helpers.presence(transaction["transaction_id"]),
      amount_value: abs_decimal(Helpers.decimal(transaction["amount"])),
      amount_currency: transaction["currency"],
      local_amount_value: abs_decimal(Helpers.decimal(transaction["local_amount"])),
      local_amount_currency: transaction["local_currency"],
      fee_value: nil,
      fee_currency: nil,
      running_balance_value: Helpers.decimal(transaction["settled_balance"]),
      running_balance_currency: transaction["currency"],
      booked_at: Helpers.datetime(transaction["settled_at"] || transaction["emitted_at"]),
      settled_at: Helpers.datetime(transaction["settled_at"]),
      provider_updated_at: Helpers.datetime(transaction["updated_at"]),
      affects_cash_balance: affects_cash_balance,
      # Runway relevance mirrors cash impact. We deliberately do NOT key off
      # Qonto's `transfer` flag: it is set on every SEPA credit transfer,
      # including payroll and vendor payments, which are real operating burn.
      # Genuine intercompany movement is excluded separately by counterparty in
      # Atlas.Finance.Sync.flag_internal_transfer/2.
      affects_runway: affects_cash_balance,
      metadata:
        Helpers.compact_map(%{
          "transaction_id" => transaction["transaction_id"],
          "operation_type" => transaction["operation_type"],
          "subject_type" => transaction["subject_type"],
          "category" => transaction["category"],
          "cashflow_category" => get_in(transaction, ["cashflow_category", "name"]),
          "cashflow_subcategory" => get_in(transaction, ["cashflow_subcategory", "name"]),
          "card_last_digits" => transaction["card_last_digits"],
          "attachment_ids" => transaction["attachment_ids"],
          "transfer" => transaction["transfer"]
        }),
      raw: transaction
    }
  end

  defp ensure_attachment_url(_config, %{"url" => url} = attachment) when is_binary(url) and url != "" do
    {:ok, attachment}
  end

  defp ensure_attachment_url(config, %{"id" => id}) when is_binary(id) and id != "" do
    case get(config, "/attachments/#{URI.encode(id)}", []) do
      {:ok, %{"attachment" => attachment}} when is_map(attachment) -> {:ok, attachment}
      {:ok, other} -> {:error, {:invalid_response, other}}
      error -> error
    end
  end

  defp ensure_attachment_url(_config, attachment), do: {:error, {:missing_attachment_url, attachment}}

  defp attachment_download(%{"probative_attachment" => %{"status" => "available", "url" => url} = probative})
       when is_binary(url) and url != "" do
    {:ok,
     %{
       url: String.replace(url, "\\u0026", "&"),
       filename: Helpers.presence(probative["file_name"]) || "qonto-probative-attachment.pdf",
       content_type: Helpers.presence(probative["file_content_type"]) || "application/pdf",
       byte_size: parse_integer(probative["file_size"]),
       probative?: true,
       attachment: probative
     }}
  end

  defp attachment_download(%{"url" => url} = attachment) when is_binary(url) and url != "" do
    {:ok,
     %{
       url: String.replace(url, "\\u0026", "&"),
       filename: Helpers.presence(attachment["file_name"]) || "qonto-attachment",
       content_type: Helpers.presence(attachment["file_content_type"]) || "application/octet-stream",
       byte_size: parse_integer(attachment["file_size"]),
       probative?: false,
       attachment: attachment
     }}
  end

  defp attachment_download(attachment), do: {:error, {:missing_attachment_url, attachment}}

  defp download_attachment_url(url, config) do
    request = Req.new(url: url, receive_timeout: receive_timeout(config))

    case Req.get(request) do
      {:ok, %Req.Response{status: status, body: body}} when status in 200..299 and is_binary(body) ->
        {:ok, body}

      {:ok, %Req.Response{status: status, body: body}} ->
        {:error, {:http, status, body}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp parse_integer(value) when is_integer(value), do: value

  defp parse_integer(value) when is_binary(value) do
    case Integer.parse(value) do
      {integer, _rest} -> integer
      :error -> nil
    end
  end

  defp parse_integer(_value), do: nil

  defp abs_decimal(nil), do: nil
  defp abs_decimal(%Decimal{} = value), do: Decimal.abs(value)

  defp normalize_direction("credit"), do: "credit"
  defp normalize_direction(_side), do: "debit"

  defp normalize_kind(operation_type, subject_type) do
    case Helpers.presence(operation_type) || Helpers.presence(subject_type) do
      nil -> "transaction"
      value -> value |> String.trim() |> String.downcase() |> String.replace(" ", "_")
    end
  end

  defp add_status_params(params) do
    Enum.reduce(@statuses, params, fn status, acc -> acc ++ [{"status[]", status}] end)
  end

  defp maybe_add_datetime_param(params, _key, nil), do: params

  defp maybe_add_datetime_param(params, key, %DateTime{} = datetime),
    do: params ++ [{key, DateTime.to_iso8601(datetime)}]

  defp get(config, path, params) do
    request =
      Req.new(url: url(config, path), receive_timeout: receive_timeout(config), headers: headers(config))
      |> maybe_put_bearer(config)
      |> Req.merge(params: params)

    case Req.get(request) do
      {:ok, %Req.Response{status: status, body: body}} when status in 200..299 ->
        {:ok, body}

      {:ok, %Req.Response{status: status, body: body}} ->
        Logger.warning("Qonto request failed: status=#{status} body=#{inspect(body)}")
        {:error, {:http, status, body}}

      {:error, reason} ->
        Logger.warning("Qonto transport error: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp post(config, path, opts) do
    body = Keyword.fetch!(opts, :body)
    filename = Keyword.fetch!(opts, :filename)
    content_type = Keyword.fetch!(opts, :content_type)

    request =
      Req.new(url: url(config, path), receive_timeout: receive_timeout(config), headers: headers(config))
      |> maybe_put_bearer(config)

    case Req.post(request,
           multipart: [
             {:file, %{body: body, filename: filename, headers: [content_type: content_type]}}
           ]
         ) do
      {:ok, %Req.Response{status: status, body: body}} when status in 200..299 ->
        {:ok, %{body: body}}

      {:ok, %Req.Response{status: status, body: body}} ->
        Logger.warning("Qonto POST request failed: status=#{status} body=#{inspect(body)}")
        {:error, {:http, status, body}}

      {:error, reason} ->
        Logger.warning("Qonto POST transport error: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp delete(config, path) do
    request =
      Req.new(url: url(config, path), receive_timeout: receive_timeout(config), headers: headers(config))
      |> maybe_put_bearer(config)

    case Req.delete(request) do
      {:ok, %Req.Response{status: status, body: body}} when status in 200..299 ->
        {:ok, body}

      {:ok, %Req.Response{status: status, body: %{"errors" => errors}}} ->
        Logger.warning("Qonto DELETE request failed: status=#{status} errors=#{inspect(errors)}")
        {:error, {:http, status, errors}}

      {:ok, %Req.Response{status: status, body: body}} ->
        Logger.warning("Qonto DELETE request failed: status=#{status} body=#{inspect(body)}")
        {:error, {:http, status, body}}

      {:error, reason} ->
        Logger.warning("Qonto DELETE transport error: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp maybe_put_bearer(request, config) do
    case Helpers.presence(config[:access_token]) do
      nil -> request
      token -> Req.merge(request, auth: {:bearer, token})
    end
  end

  defp headers(config) do
    [{"accept", "application/json"}]
    |> maybe_add_api_key_header(config)
    |> maybe_add_staging_token(config)
  end

  defp maybe_add_api_key_header(headers, config) do
    case {Helpers.presence(config[:access_token]), Helpers.presence(config[:sign_in]),
          Helpers.presence(config[:secret_key])} do
      {nil, sign_in, secret_key} when is_binary(sign_in) and is_binary(secret_key) ->
        headers ++ [{"authorization", "#{sign_in}:#{secret_key}"}]

      _other ->
        headers
    end
  end

  defp maybe_add_staging_token(headers, config) do
    case Helpers.presence(config[:staging_token]) do
      nil -> headers
      token -> headers ++ [{"x-qonto-staging-token", token}]
    end
  end

  defp base_url(config), do: String.trim_trailing(config[:base_url] || @base_url, "/")

  defp url(config, path) do
    config
    |> base_url()
    |> URI.new!()
    |> URI.append_path(path)
    |> URI.to_string()
  end

  defp receive_timeout(config) do
    case config[:receive_timeout] do
      timeout when is_integer(timeout) and timeout > 0 -> timeout
      _other -> @receive_timeout
    end
  end
end

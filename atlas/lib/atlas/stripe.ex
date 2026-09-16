defmodule Atlas.Stripe do
  @moduledoc """
  Thin Stripe REST client.

  Reads the API key at call time from `:atlas, :stripe, :api_key` (set in
  `runtime.exs` from `STRIPE_API_KEY`). When no key is configured the public
  helpers return `:disabled` so callers can render gracefully in dev/test.
  """

  require Logger

  @base_url "https://api.stripe.com/v1"
  @default_invoice_limit 25
  @default_receive_timeout 5_000

  defmodule Invoice do
    @moduledoc false
    defstruct [
      :id,
      :number,
      :livemode,
      :due_date,
      :amount_value,
      :amount_currency,
      :status,
      :hosted_url,
      :pdf_url,
      :dashboard_url,
      :customer_id,
      :customer_name,
      :customer_email
    ]
  end

  defmodule Customer do
    @moduledoc false
    defstruct [
      :id,
      :name,
      :email,
      :address,
      :description,
      :livemode,
      :dashboard_url,
      :metadata
    ]
  end

  @doc """
  Fetches a Stripe customer by id.

  Returns `{:ok, %Customer{}}` on success, `{:error, reason}` on transport or
  HTTP error, or `:disabled` when `STRIPE_API_KEY` is not configured.
  """
  def get_customer(customer_id, opts \\ []) when is_binary(customer_id) do
    case api_key(opts) do
      nil ->
        :disabled

      key ->
        request =
          Req.new(
            url: endpoint_url(opts, ["customers", customer_id]),
            auth: {:bearer, key},
            receive_timeout: receive_timeout(opts)
          )

        case get_fun(opts).(request) do
          {:ok, %Req.Response{status: 200, body: %{} = customer}} ->
            {:ok, decode_customer(customer)}

          {:ok, %Req.Response{status: status, body: body}} ->
            Logger.warning("Stripe get_customer failed: status=#{status} body=#{inspect(body)}")
            {:error, {:http, status}}

          {:error, reason} ->
            Logger.warning("Stripe get_customer transport error: #{inspect(reason)}")
            {:error, reason}
        end
    end
  end

  @doc """
  Updates writable fields on a Stripe customer.

  `attrs` may include `:name`, `:email`, `:description`, `:address`, and
  `:metadata`. Returns `{:ok, %Customer{}}` on success, `{:error, reason}` on
  transport or HTTP error, or `:disabled` when `STRIPE_API_KEY` is not
  configured.
  """
  def update_customer(customer_id, attrs, opts \\ []) when is_binary(customer_id) and is_map(attrs) do
    case api_key(opts) do
      nil ->
        :disabled

      key ->
        request =
          Req.new(
            url: endpoint_url(opts, ["customers", customer_id]),
            auth: {:bearer, key},
            receive_timeout: receive_timeout(opts)
          )
          |> Req.merge(form: customer_form(attrs))

        case post_fun(opts).(request) do
          {:ok, %Req.Response{status: 200, body: %{} = customer}} ->
            {:ok, decode_customer(customer)}

          {:ok, %Req.Response{status: status, body: body}} ->
            Logger.warning("Stripe update_customer failed: status=#{status} body=#{inspect(body)}")
            {:error, {:http, status}}

          {:error, reason} ->
            Logger.warning("Stripe update_customer transport error: #{inspect(reason)}")
            {:error, reason}
        end
    end
  end

  @doc """
  Creates a draft invoice and attaches invoice items to it.

  The invoice is created with `auto_advance=false` so Stripe does not finalize,
  send, or attempt payment without an explicit follow-up action. Returns
  `{:ok, %Invoice{}}` with the refreshed invoice after line items are attached,
  `{:error, reason}` on transport or HTTP error, or `:disabled` when
  `STRIPE_API_KEY` is not configured.
  """
  def create_draft_invoice(customer_id, attrs, opts \\ []) when is_binary(customer_id) and is_map(attrs) do
    case api_key(opts) do
      nil ->
        :disabled

      key ->
        with {:ok, invoice} <- create_invoice(customer_id, attrs, key, opts),
             :ok <- create_invoice_items(customer_id, invoice.id, Map.get(attrs, :line_items, []), key, opts) do
          retrieve_invoice(invoice.id, key, opts)
        end
    end
  end

  @doc """
  Attaches line items to an existing draft invoice and returns the refreshed
  invoice.

  Retrieves the invoice first to resolve its customer id, then posts each line
  item to `/invoiceitems`. Returns `{:ok, %Invoice{}}` on success,
  `{:error, reason}` on transport or HTTP error, or `:disabled` when
  `STRIPE_API_KEY` is not configured.
  """
  def add_invoice_items(invoice_id, line_items, opts \\ []) when is_binary(invoice_id) and is_list(line_items) do
    case api_key(opts) do
      nil ->
        :disabled

      key ->
        with {:ok, %Invoice{} = invoice} <- retrieve_invoice(invoice_id, key, opts),
             {:ok, customer_id} <- invoice_customer_id(invoice),
             :ok <- create_invoice_items(customer_id, invoice.id, line_items, key, opts) do
          retrieve_invoice(invoice.id, key, opts)
        end
    end
  end

  defp invoice_customer_id(%Invoice{customer_id: customer_id}) when is_binary(customer_id) and customer_id != "",
    do: {:ok, customer_id}

  defp invoice_customer_id(_invoice), do: {:error, :missing_invoice_customer}

  @doc """
  Updates writable fields on a Stripe invoice (`description`, `footer`,
  `days_until_due`, `metadata`) and returns the refreshed invoice.

  `metadata` is merged on Stripe's side: keys set in `attrs[:metadata]` are
  added or replaced, other keys remain. Returns `{:ok, %Invoice{}}` on
  success, `{:error, reason}` on transport or HTTP error, or `:disabled` when
  `STRIPE_API_KEY` is not configured.
  """
  def update_invoice(invoice_id, attrs, opts \\ []) when is_binary(invoice_id) and is_map(attrs) do
    case api_key(opts) do
      nil ->
        :disabled

      key ->
        post_invoice_update(invoice_id, attrs, key, opts)
    end
  end

  defp post_invoice_update(invoice_id, attrs, key, opts) do
    request =
      Req.new(
        url: endpoint_url(opts, "/invoices/#{invoice_id}"),
        auth: {:bearer, key},
        receive_timeout: receive_timeout(opts)
      )
      |> Req.merge(form: invoice_update_form(attrs))

    case post_fun(opts).(request) do
      {:ok, %Req.Response{status: 200, body: %{} = invoice}} ->
        {:ok, decode_invoice(invoice)}

      {:ok, %Req.Response{status: status, body: body}} ->
        Logger.warning("Stripe update_invoice failed: status=#{status} body=#{inspect(body)}")
        {:error, {:http, status}}

      {:error, reason} ->
        Logger.warning("Stripe update_invoice transport error: #{inspect(reason)}")
        {:error, reason}
    end
  end

  @doc """
  Fetches a Stripe invoice by id.

  Returns `{:ok, %Invoice{}}` on success, `{:error, reason}` on transport or
  HTTP error, or `:disabled` when `STRIPE_API_KEY` is not configured.
  """
  def get_invoice(invoice_id, opts \\ []) when is_binary(invoice_id) do
    case api_key(opts) do
      nil -> :disabled
      key -> retrieve_invoice(invoice_id, key, opts)
    end
  end

  @doc """
  Lists invoices for a Stripe customer, newest first.

  Returns `{:ok, [%Invoice{}]}` on success, `{:error, reason}` on transport or
  HTTP error, or `:disabled` when `STRIPE_API_KEY` is not configured.
  """
  def list_invoices(customer_id, opts \\ []) when is_binary(customer_id) do
    case api_key(opts) do
      nil ->
        :disabled

      key ->
        limit = Keyword.get(opts, :limit, @default_invoice_limit)
        url = endpoint_url(opts, "/invoices")

        request =
          Req.new(url: url, auth: {:bearer, key}, receive_timeout: receive_timeout(opts))
          |> Req.merge(params: [customer: customer_id, limit: limit])

        case request_fun(opts).(request) do
          {:ok, %Req.Response{status: 200, body: %{"data" => data}}} ->
            {:ok, Enum.map(data, &decode_invoice/1)}

          {:ok, %Req.Response{status: status, body: body}} ->
            Logger.warning("Stripe list_invoices failed: status=#{status} body=#{inspect(body)}")
            {:error, {:http, status}}

          {:error, reason} ->
            Logger.warning("Stripe list_invoices transport error: #{inspect(reason)}")
            {:error, reason}
        end
    end
  end

  defp create_invoice(customer_id, attrs, key, opts) do
    request =
      Req.new(url: endpoint_url(opts, "/invoices"), auth: {:bearer, key}, receive_timeout: receive_timeout(opts))
      |> Req.merge(
        form: invoice_form(customer_id, attrs),
        headers: idempotency_headers(attrs[:idempotency_key])
      )

    case post_fun(opts).(request) do
      {:ok, %Req.Response{status: 200, body: %{} = invoice}} ->
        {:ok, decode_invoice(invoice)}

      {:ok, %Req.Response{status: status, body: body}} ->
        Logger.warning("Stripe create_draft_invoice failed: status=#{status} body=#{inspect(body)}")
        {:error, {:http, status}}

      {:error, reason} ->
        Logger.warning("Stripe create_draft_invoice transport error: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp create_invoice_items(_customer_id, _invoice_id, [], _key, _opts), do: :ok

  defp create_invoice_items(customer_id, invoice_id, line_items, key, opts) when is_list(line_items) do
    line_items
    |> Enum.with_index(1)
    |> Enum.reduce_while(:ok, fn {line_item, index}, :ok ->
      case create_invoice_item(customer_id, invoice_id, line_item, index, key, opts) do
        :ok -> {:cont, :ok}
        {:error, reason} -> {:halt, {:error, {:invoice_item, invoice_id, reason}}}
      end
    end)
  end

  defp create_invoice_item(customer_id, invoice_id, line_item, index, key, opts) do
    request =
      Req.new(url: endpoint_url(opts, "/invoiceitems"), auth: {:bearer, key}, receive_timeout: receive_timeout(opts))
      |> Req.merge(
        form: invoice_item_form(customer_id, invoice_id, line_item),
        headers: idempotency_headers(line_item_idempotency_key(line_item, index))
      )

    case post_fun(opts).(request) do
      {:ok, %Req.Response{status: 200}} ->
        :ok

      {:ok, %Req.Response{status: status, body: body}} ->
        Logger.warning("Stripe create_invoice_item failed: status=#{status} body=#{inspect(body)}")
        {:error, {:http, status}}

      {:error, reason} ->
        Logger.warning("Stripe create_invoice_item transport error: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp retrieve_invoice(invoice_id, key, opts) do
    request =
      Req.new(
        url: endpoint_url(opts, "/invoices/#{invoice_id}"),
        auth: {:bearer, key},
        receive_timeout: receive_timeout(opts)
      )

    case get_fun(opts).(request) do
      {:ok, %Req.Response{status: 200, body: %{} = invoice}} ->
        {:ok, decode_invoice(invoice)}

      {:ok, %Req.Response{status: status, body: body}} ->
        Logger.warning("Stripe retrieve_invoice failed: status=#{status} body=#{inspect(body)}")
        {:error, {:http, status}}

      {:error, reason} ->
        Logger.warning("Stripe retrieve_invoice transport error: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp invoice_form(customer_id, attrs) do
    [
      {"customer", customer_id},
      {"collection_method", to_string(Map.get(attrs, :collection_method, "send_invoice"))},
      {"auto_advance", "false"}
    ]
    |> maybe_put_form("currency", currency_form_value(attrs[:currency]))
    |> maybe_put_form("days_until_due", attrs[:days_until_due])
    |> maybe_put_form("description", attrs[:description])
    |> maybe_put_form("footer", attrs[:footer])
    |> append_metadata(attrs[:metadata])
  end

  defp currency_form_value(nil), do: nil
  defp currency_form_value(""), do: nil
  defp currency_form_value(currency) when is_binary(currency), do: String.downcase(currency)

  defp invoice_update_form(attrs) do
    []
    |> maybe_put_form("description", attrs[:description])
    |> maybe_put_form("footer", attrs[:footer])
    |> maybe_put_form("days_until_due", attrs[:days_until_due])
    |> append_metadata(attrs[:metadata])
  end

  defp invoice_item_form(customer_id, invoice_id, line_item) do
    [
      {"customer", customer_id},
      {"invoice", invoice_id},
      {"currency", line_item.currency |> to_string() |> String.downcase()},
      {"description", line_item.description}
    ]
    |> append_invoice_item_amount(line_item)
    |> maybe_put_period("start", line_item[:period_start])
    |> maybe_put_period("end", line_item[:period_end])
    |> append_metadata(line_item[:metadata])
  end

  defp append_invoice_item_amount(form, %{quantity: quantity, unit_amount_decimal: unit_amount_decimal})
       when is_integer(quantity) and quantity > 0 and is_binary(unit_amount_decimal) and unit_amount_decimal != "" do
    form ++ [{"quantity", quantity}, {"unit_amount_decimal", unit_amount_decimal}]
  end

  defp append_invoice_item_amount(form, line_item), do: form ++ [{"amount", line_item.amount_cents}]

  defp maybe_put_form(form, _key, nil), do: form
  defp maybe_put_form(form, _key, ""), do: form
  defp maybe_put_form(form, key, value), do: form ++ [{key, value}]

  defp maybe_put_period(form, _key, nil), do: form

  defp maybe_put_period(form, key, %Date{} = date) do
    form ++ [{"period[#{key}]", date |> DateTime.new!(~T[00:00:00], "Etc/UTC") |> DateTime.to_unix()}]
  end

  defp maybe_put_period(form, _key, _value), do: form

  defp append_metadata(form, metadata) when is_map(metadata) do
    Enum.reduce(metadata, form, fn
      {_key, nil}, acc ->
        acc

      {key, value}, acc ->
        acc ++ [{"metadata[#{key}]", to_string(value)}]
    end)
  end

  defp append_metadata(form, _metadata), do: form

  defp idempotency_headers(nil), do: []
  defp idempotency_headers(""), do: []
  defp idempotency_headers(key) when is_binary(key), do: [{"idempotency-key", key}]

  defp line_item_idempotency_key(line_item, index) do
    case line_item[:idempotency_key] do
      value when is_binary(value) and value != "" -> value
      _other -> nil
    end
    |> case do
      nil -> nil
      key -> "#{key}:line-item:#{index}"
    end
  end

  @doc """
  Lists invoices across all customers filtered by status, newest first.

  Returns `{:ok, [%Invoice{}]}` on success, `{:error, reason}` on transport or
  HTTP error, or `:disabled` when `STRIPE_API_KEY` is not configured.
  """
  def list_invoices_by_status(status, opts \\ []) when is_binary(status) do
    case api_key(opts) do
      nil ->
        :disabled

      key ->
        limit = Keyword.get(opts, :limit, @default_invoice_limit)
        url = endpoint_url(opts, "/invoices")

        request =
          Req.new(url: url, auth: {:bearer, key}, receive_timeout: receive_timeout(opts))
          |> Req.merge(params: [status: status, limit: limit])

        case request_fun(opts).(request) do
          {:ok, %Req.Response{status: 200, body: %{"data" => data}}} ->
            {:ok, Enum.map(data, &decode_invoice/1)}

          {:ok, %Req.Response{status: status_code, body: body}} ->
            Logger.warning("Stripe list_invoices_by_status failed: status=#{status_code} body=#{inspect(body)}")
            {:error, {:http, status_code}}

          {:error, reason} ->
            Logger.warning("Stripe list_invoices_by_status transport error: #{inspect(reason)}")
            {:error, reason}
        end
    end
  end

  @doc """
  Lists a page of invoices across all customers using Stripe cursor pagination.

  Accepts `:limit`, `:after` (translates to `starting_after`) and `:before`
  (translates to `ending_before`). Returns
  `{:ok, %{invoices: [%Invoice{}], has_more: boolean()}}` on success so callers
  can wire Prev/Next controls. Returns `{:error, reason}` on transport or HTTP
  error, or `:disabled` when `STRIPE_API_KEY` is not configured.
  """
  def list_invoices_page(opts \\ []) do
    case api_key(opts) do
      nil ->
        :disabled

      key ->
        limit = Keyword.get(opts, :limit, @default_invoice_limit)
        after_cursor = Keyword.get(opts, :after)
        before_cursor = if after_cursor in [nil, ""], do: Keyword.get(opts, :before)

        params =
          [limit: limit]
          |> maybe_put_param(:status, Keyword.get(opts, :status))
          |> maybe_put_param(:starting_after, after_cursor)
          |> maybe_put_param(:ending_before, before_cursor)

        request =
          Req.new(url: endpoint_url(opts, "/invoices"), auth: {:bearer, key}, receive_timeout: receive_timeout(opts))
          |> Req.merge(params: params)

        case request_fun(opts).(request) do
          {:ok, %Req.Response{status: 200, body: %{"data" => data} = body}} ->
            {:ok, %{invoices: Enum.map(data, &decode_invoice/1), has_more: body["has_more"] == true}}

          {:ok, %Req.Response{status: status_code, body: body}} ->
            Logger.warning("Stripe list_invoices_page failed: status=#{status_code} body=#{inspect(body)}")
            {:error, {:http, status_code}}

          {:error, reason} ->
            Logger.warning("Stripe list_invoices_page transport error: #{inspect(reason)}")
            {:error, reason}
        end
    end
  end

  defp maybe_put_param(params, _key, nil), do: params
  defp maybe_put_param(params, _key, ""), do: params
  defp maybe_put_param(params, key, value), do: Keyword.put(params, key, value)

  defp decode_invoice(%{} = invoice) do
    %Invoice{
      id: invoice["id"],
      number: invoice["number"],
      livemode: invoice["livemode"],
      due_date: epoch_to_date(invoice["due_date"] || invoice["next_payment_attempt"] || invoice["period_end"]),
      amount_value: cents_to_decimal(invoice["amount_due"] || invoice["amount_paid"] || invoice["total"]),
      amount_currency: invoice["currency"] && String.upcase(invoice["currency"]),
      status: invoice["status"],
      hosted_url: invoice["hosted_invoice_url"],
      pdf_url: invoice["invoice_pdf"],
      dashboard_url: invoice_dashboard_url(invoice["id"], invoice["livemode"]),
      customer_id: invoice["customer"],
      customer_name: presence(invoice["customer_name"]),
      customer_email: presence(invoice["customer_email"])
    }
  end

  defp presence(nil), do: nil

  defp presence(value) when is_binary(value) do
    case String.trim(value) do
      "" -> nil
      trimmed -> trimmed
    end
  end

  defp epoch_to_date(nil), do: nil

  defp epoch_to_date(epoch) when is_integer(epoch) do
    epoch
    |> DateTime.from_unix!()
    |> DateTime.to_date()
  end

  defp cents_to_decimal(nil), do: nil

  defp cents_to_decimal(cents) when is_integer(cents) do
    Decimal.div(Decimal.new(cents), Decimal.new(100))
  end

  @doc """
  Searches Stripe customers using the search API.

  `query` is a Stripe search query string such as `name:'Acme Corp'` or
  `email~"@notion.so"`. Returns `{:ok, [%Customer{}]}` on success,
  `{:error, reason}` on transport or HTTP error, or `:disabled` when
  `STRIPE_API_KEY` is not configured.
  """
  def search_customers(query, opts \\ []) when is_binary(query) do
    case api_key(opts) do
      nil ->
        :disabled

      key ->
        limit = Keyword.get(opts, :limit, 10)

        request =
          Req.new(
            url: endpoint_url(opts, "/customers/search"),
            auth: {:bearer, key},
            receive_timeout: receive_timeout(opts)
          )
          |> Req.merge(params: [query: query, limit: limit])

        case request_fun(opts).(request) do
          {:ok, %Req.Response{status: 200, body: %{"data" => data}}} ->
            {:ok, Enum.map(data, &decode_customer/1)}

          {:ok, %Req.Response{status: status, body: body}} ->
            Logger.warning("Stripe search_customers failed: status=#{status} body=#{inspect(body)}")
            {:error, {:http, status}}

          {:error, reason} ->
            Logger.warning("Stripe search_customers transport error: #{inspect(reason)}")
            {:error, reason}
        end
    end
  end

  @doc """
  Creates a Stripe customer.

  `attrs` may include `:name`, `:email`, `:description`, `:address`
  (`%{line1, line2, city, state, postal_code, country}`), and `:metadata`.
  Returns `{:ok, %Customer{}}` on success, `{:error, reason}` on transport or
  HTTP error, or `:disabled` when `STRIPE_API_KEY` is not configured.
  """
  def create_customer(attrs, opts \\ []) when is_map(attrs) do
    case api_key(opts) do
      nil ->
        :disabled

      key ->
        request =
          Req.new(
            url: endpoint_url(opts, "/customers"),
            auth: {:bearer, key},
            receive_timeout: receive_timeout(opts)
          )
          |> Req.merge(
            form: customer_form(attrs),
            headers: idempotency_headers(attrs[:idempotency_key])
          )

        case post_fun(opts).(request) do
          {:ok, %Req.Response{status: 200, body: %{} = customer}} ->
            {:ok, decode_customer(customer)}

          {:ok, %Req.Response{status: status, body: body}} ->
            Logger.warning("Stripe create_customer failed: status=#{status} body=#{inspect(body)}")
            {:error, {:http, status}}

          {:error, reason} ->
            Logger.warning("Stripe create_customer transport error: #{inspect(reason)}")
            {:error, reason}
        end
    end
  end

  defp customer_form(attrs) do
    []
    |> maybe_put_form("name", attrs[:name])
    |> maybe_put_form("email", attrs[:email])
    |> maybe_put_form("description", attrs[:description])
    |> append_address(attrs[:address])
    |> append_metadata(attrs[:metadata])
  end

  defp append_address(form, nil), do: form
  defp append_address(form, address) when is_map(address) and map_size(address) == 0, do: form

  defp append_address(form, address) when is_map(address) do
    Enum.reduce([:line1, :line2, :city, :state, :postal_code, :country], form, fn key, acc ->
      maybe_put_form(acc, "address[#{key}]", Map.get(address, key) || Map.get(address, to_string(key)))
    end)
  end

  defp decode_customer(%{} = customer) do
    %Customer{
      id: customer["id"],
      name: presence(customer["name"]),
      email: presence(customer["email"]),
      address: decode_customer_address(customer["address"]),
      description: presence(customer["description"]),
      livemode: customer["livemode"],
      dashboard_url: customer_dashboard_url(customer["id"], customer["livemode"]),
      metadata: customer["metadata"] || %{}
    }
  end

  defp decode_customer_address(address) when is_map(address) do
    %{
      line1: presence(address["line1"]),
      line2: presence(address["line2"]),
      city: presence(address["city"]),
      state: presence(address["state"]),
      postal_code: presence(address["postal_code"]),
      country: presence(address["country"])
    }
    |> Enum.reject(fn {_key, value} -> is_nil(value) end)
    |> Map.new()
    |> case do
      address when map_size(address) == 0 -> nil
      address -> address
    end
  end

  defp decode_customer_address(_address), do: nil

  defp customer_dashboard_url(customer_id, livemode) when is_binary(customer_id) do
    case livemode do
      false -> "https://dashboard.stripe.com/test/customers/#{customer_id}"
      _other -> "https://dashboard.stripe.com/customers/#{customer_id}"
    end
  end

  defp customer_dashboard_url(_customer_id, _livemode), do: nil

  defp request_fun(opts), do: Keyword.get(opts, :request, &Req.get/1)
  defp get_fun(opts), do: Keyword.get(opts, :get, &Req.get/1)
  defp post_fun(opts), do: Keyword.get(opts, :post, &Req.post/1)

  defp api_key(opts) do
    if Keyword.has_key?(opts, :api_key) do
      Keyword.get(opts, :api_key)
    else
      Application.get_env(:atlas, :stripe, [])[:api_key]
    end
  end

  defp base_url(opts) do
    opts
    |> Keyword.get(:base_url, @base_url)
    |> case do
      value when value in [nil, ""] -> @base_url
      value -> String.trim_trailing(value, "/")
    end
  end

  defp endpoint_url(opts, path_segments) when is_list(path_segments) do
    path =
      path_segments
      |> Enum.map(&to_string/1)
      |> Enum.map_join("/", &encode_path_segment/1)

    endpoint_url(opts, "/" <> path)
  end

  defp endpoint_url(opts, path) do
    opts
    |> base_url()
    |> URI.parse()
    |> URI.append_path(path)
    |> URI.to_string()
  end

  defp encode_path_segment(segment), do: URI.encode(segment, &URI.char_unreserved?/1)

  defp receive_timeout(opts) do
    case Keyword.get(opts, :receive_timeout, @default_receive_timeout) do
      timeout when is_integer(timeout) and timeout > 0 -> timeout
      _other -> @default_receive_timeout
    end
  end

  defp invoice_dashboard_url(invoice_id, livemode) when is_binary(invoice_id) do
    case livemode do
      false -> "https://dashboard.stripe.com/test/invoices/#{invoice_id}"
      _other -> "https://dashboard.stripe.com/invoices/#{invoice_id}"
    end
  end

  defp invoice_dashboard_url(_invoice_id, _livemode), do: nil
end

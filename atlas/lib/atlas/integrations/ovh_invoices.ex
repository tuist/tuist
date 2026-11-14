defmodule Atlas.Integrations.OVHInvoices do
  @moduledoc "Reads OVH US bills through the caller's own ovh-orders OAuth grant."

  alias Atlas.Audit
  alias Atlas.Documents
  alias Atlas.MCP
  alias Atlas.MCP.Proxy
  alias Atlas.Moodboard.SafeHTTP

  @server "ovh-orders"
  @api "https://api.us.ovhcloud.com/1.0"

  def list(user, args) do
    with {:ok, params} <- date_params(args),
         {:ok, token} <- access_token(user),
         {:ok, ids} when is_list(ids) <- get(token, "/me/bill", params) do
      Audit.record("ovh.invoices_listed", %{metadata: %{count: length(ids)}}, actor: user)
      {:ok, %{invoice_ids: ids}}
    else
      {:ok, _body} -> {:error, "OVH returned an invalid invoice list."}
      error -> error
    end
  end

  def save(user, invoice_id) do
    with true <- is_binary(invoice_id) and Regex.match?(~r/\A[A-Za-z0-9_-]+\z/, invoice_id),
         {:ok, token} <- access_token(user),
         {:ok, invoice} <- get(token, "/me/bill/#{invoice_id}"),
         {:ok, summary} <- summary(invoice, invoice_id),
         {:ok, url} <- get(token, "/me/bill/#{invoice_id}/download", extension: "pdf"),
         {:ok, body} <- fetch_pdf(url),
         {:ok, document} <- store(user, invoice_id, body) do
      Audit.record(
        "ovh.invoice_saved",
        %{
          target_type: "document",
          target_id: document.id,
          metadata: %{invoice_id: invoice_id, path: "/documents/#{document.id}"}
        },
        actor: user
      )

      {:ok,
       Map.merge(summary, %{
         document_id: document.id,
         filename: document.original_filename,
         content_type: document.content_type,
         byte_size: document.byte_size
       })}
    else
      false -> {:error, "invoice_id must contain only letters, digits, underscores or hyphens."}
      error -> error
    end
  end

  defp access_token(user) do
    with {:ok, server} <- Proxy.fetch_server(@server),
         false <- server.shared_oauth,
         true <- Proxy.user_allowed?(server, user),
         {:ok, token} <- MCP.access_token_for(user, server) do
      {:ok, token}
    else
      _ -> {:error, "Connect your own #{@server} account at #{AtlasWeb.Endpoint.url()}/admin/mcps, then retry."}
    end
  end

  defp get(token, path, params \\ []) do
    case Req.request(
           method: :get,
           url: @api <> path,
           auth: {:bearer, token},
           params: params,
           retry: false,
           redirect: false
         ) do
      {:ok, %{status: 200, body: body}} ->
        {:ok, body}

      {:ok, %{status: status}} when status in [401, 403] ->
        {:error,
         "OVH rejected invoice access (HTTP #{status}). Check your #{@server} connection at " <>
           "#{AtlasWeb.Endpoint.url()}/admin/mcps and its account:apiovh:me/bill/get and " <>
           "account:apiovh:me/download/get IAM permissions."}

      {:ok, %{status: 404}} ->
        {:error, "OVH could not find that invoice in your account."}

      {:ok, %{status: status}} ->
        {:error, "OVH invoice request failed (HTTP #{status})."}

      {:error, _reason} ->
        {:error, "Could not reach OVH's invoice API. Try again shortly."}
    end
  end

  # The API's pdfUrl may require a browser session. /download generates the
  # download link; fetch it without forwarding the OAuth token, pinning public DNS.
  defp fetch_pdf(url) do
    case SafeHTTP.fetch(url) do
      {:ok, %{status: 200, body: <<"%PDF-", _rest::binary>> = body}} -> {:ok, body}
      _ -> {:error, "OVH's download did not return a public PDF (maximum 2 MB). No document was saved."}
    end
  end

  defp store(user, invoice_id, body) do
    attrs = %{
      "title" => "OVH #{invoice_id}",
      "original_filename" => "#{invoice_id}.pdf",
      "content_type" => "application/pdf",
      "source" => "upload",
      "uploaded_by_id" => user.id,
      "attributes" => %{"provider" => "ovh", "invoice_id" => invoice_id}
    }

    case Documents.create_from_binary(body, attrs, audit_actor: user) do
      {:ok, document} -> {:ok, document}
      {:error, _reason} -> {:error, "Could not save the OVH invoice to the document library. Try again shortly."}
    end
  end

  defp summary(
         %{"billId" => id, "date" => date, "priceWithTax" => %{"value" => amount, "currencyCode" => currency}},
         id
       )
       when is_binary(date) and is_number(amount) and is_binary(currency) do
    {:ok, %{invoice_id: id, date: date, amount: to_string(amount), currency: currency}}
  end

  defp summary(_invoice, _id), do: {:error, "OVH returned invalid invoice details. No document was saved."}

  defp date_params(args) do
    from = args["date_from"]
    to = args["date_to"]

    with {:ok, from} <- datetime(from),
         {:ok, to} <- datetime(to),
         true <- is_nil(from) or is_nil(to) or DateTime.compare(from, to) != :gt do
      {:ok,
       Enum.flat_map([{"date.from", from}, {"date.to", to}], fn
         {_key, nil} -> []
         {key, date} -> [{key, DateTime.to_iso8601(date)}]
       end)}
    else
      _ -> {:error, "Use ISO-8601 datetimes with time zones and date_from no later than date_to."}
    end
  end

  defp datetime(nil), do: {:ok, nil}

  defp datetime(value) when is_binary(value) do
    case DateTime.from_iso8601(value) do
      {:ok, date, _offset} -> {:ok, date}
      _ -> {:error, :invalid_datetime}
    end
  end

  defp datetime(_value), do: {:error, :invalid_datetime}
end

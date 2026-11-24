defmodule Atlas.MCP.Tools.FinanceCreateTransferRequest do
  @moduledoc """
  Prepares outgoing SEPA payments as one pending transfer request in Qonto.
  Nothing is paid until a member with review rights approves the request in
  Qonto with strong customer authentication.
  """

  use Atlas.MCP.Tool,
    name: "finance_create_transfer_request",
    schema: %{
      "type" => "object",
      "properties" => %{
        "source_key" => %{
          "type" => "string",
          "description" => "Key of the Qonto finance source to request the transfers from (from list_finance_accounts)."
        },
        "note" => %{
          "type" => "string",
          "description" => "What the payments are for, shown to the approver in Qonto."
        },
        "transfers" => %{
          "type" => "array",
          "minItems" => 1,
          "maxItems" => 400,
          "items" => %{
            "type" => "object",
            "properties" => %{
              "amount" => %{
                "type" => "string",
                "description" => "Amount in EUR with at most two decimals, for example 1713.60."
              },
              "iban" => %{"type" => "string", "description" => "Beneficiary IBAN. Spaces are ignored."},
              "name" => %{"type" => "string", "maxLength" => 140, "description" => "Beneficiary name."},
              "reference" => %{
                "type" => "string",
                "maxLength" => 140,
                "description" => "Payment reference the beneficiary sees, usually the invoice number."
              }
            },
            "required" => ["amount", "iban", "name", "reference"],
            "additionalProperties" => false
          }
        },
        "scheduled_date" => %{
          "type" => "string",
          "description" =>
            "Date (YYYY-MM-DD) the transfers execute once approved. Defaults to the approval day or next banking day."
        },
        "debit_iban" => %{
          "type" => "string",
          "description" => "IBAN of the Qonto account to pay from. Defaults to the organization's main account."
        }
      },
      "required" => ["source_key", "note", "transfers"],
      "additionalProperties" => false
    },
    output_schema: %{
      "type" => "object",
      "properties" => %{
        "id" => %{"type" => "string"},
        "status" => %{"type" => ["string", "null"]},
        "total_amount" => %{"type" => ["string", "null"]},
        "currency" => %{"type" => ["string", "null"]},
        "transfer_count" => %{"type" => ["integer", "null"]},
        "scheduled_date" => %{"type" => ["string", "null"]},
        "message" => %{"type" => "string"}
      },
      "required" => ["id", "status", "total_amount", "currency", "transfer_count", "scheduled_date", "message"],
      "additionalProperties" => false
    }

  alias Atlas.Audit
  alias Atlas.Connections
  alias Atlas.Finance.Config
  alias Atlas.Finance.Providers.Qonto
  alias Atlas.MCP.Tool

  @scopes ["request_transfers.write"]

  @impl EMCP.Tool
  def description do
    "Prepare outgoing EUR SEPA payments as one pending transfer request in Qonto, for example to pay vendor invoices. Nothing is paid until someone with review rights approves the request in Qonto with strong customer authentication. Retrying the same request does not create a duplicate. Requires the finance:write scope and the caller's own Qonto connection in Atlas settings (Connections)."
  end

  def execute(conn, %{"source_key" => source_key, "note" => note, "transfers" => transfers} = args) do
    with :ok <- Tool.authorize_scope(conn, "finance:write", "Finance tools"),
         {:ok, source} <- fetch_qonto_source(source_key),
         {:ok, transfers} <- normalize_transfers(transfers),
         {:ok, scheduled_date} <- normalize_date(args["scheduled_date"]) do
      request = %{
        note: note,
        transfers: transfers,
        scheduled_date: scheduled_date,
        debit_iban: args["debit_iban"] && normalize_iban(args["debit_iban"])
      }

      case create_request(Tool.current_user(conn), source, request) do
        {:ok, created} ->
          Audit.record("finance_transfer_request.created", %{
            target_type: "finance_transfer_request",
            target_id: created["id"],
            target_label: note,
            metadata: %{
              "source_key" => source_key,
              "total_amount" => created["total_transfers_amount"],
              "transfers" => Enum.map(transfers, &Map.take(&1, [:name, :amount, :reference]))
            }
          })

          {:ok,
           %{
             id: created["id"],
             status: created["status"],
             total_amount: created["total_transfers_amount"],
             currency: created["total_transfers_amount_currency"],
             transfer_count: created["total_transfers_count"],
             scheduled_date: created["scheduled_date"],
             message: "Transfer request created. Approve it in Qonto under Requests to send the payments."
           }}

        {:error, reason} when reason in [:not_connected, :needs_authorization, :insufficient_scope] ->
          {:error,
           "Qonto transfer requests need your own Qonto connection. Connect or reconnect Qonto at #{AtlasWeb.Endpoint.url()}/settings/connections, then retry."}

        {:error, {:http, status, body}} ->
          {:error, "Qonto rejected the transfer request (HTTP #{status}): #{inspect(body)}"}

        {:error, reason} ->
          {:error, "Could not reach Qonto: #{inspect(reason)}"}
      end
    end
  end

  def execute(_conn, _args), do: {:error, "source_key, note, and transfers are required."}

  # Qonto accepts transfer requests only with OAuth, so the request is made with
  # the caller's own grant and Qonto records them as its initiator. A 401 before
  # the recorded expiry gets one refreshed token and one retry; the idempotency
  # key makes that retry safe.
  defp create_request(user, source, request) do
    with {:ok, token} <- Connections.access_token(user, "qonto", @scopes) do
      case Qonto.create_multi_transfer_request(oauth_source(source, token), request) do
        {:error, {:http, 401, _body}} ->
          with {:ok, refreshed} <- Connections.refresh_access_token(user, "qonto", @scopes, token) do
            Qonto.create_multi_transfer_request(oauth_source(source, refreshed), request)
          end

        result ->
          result
      end
    end
  end

  defp oauth_source(source, token), do: source |> Map.drop([:sign_in, :secret_key]) |> Map.put(:access_token, token)

  defp fetch_qonto_source(source_key) do
    case Config.fetch_source(source_key) do
      {:ok, %{provider: :qonto} = source} ->
        {:ok, source}

      _other ->
        {:error,
         "No Qonto finance source with key '#{source_key}'. Qonto source keys: #{Enum.join(qonto_source_keys(), ", ")}."}
    end
  end

  defp qonto_source_keys do
    for %{provider: :qonto, key: key} <- Config.configured_sources(), do: key
  end

  defp normalize_transfers(transfers) do
    transfers
    |> Enum.with_index()
    |> Enum.reduce_while({:ok, []}, fn {transfer, index}, {:ok, acc} ->
      case normalize_transfer(transfer) do
        {:ok, normalized} -> {:cont, {:ok, [normalized | acc]}}
        {:error, message} -> {:halt, {:error, "transfers[#{index}]: #{message}"}}
      end
    end)
    |> case do
      {:ok, normalized} -> {:ok, Enum.reverse(normalized)}
      error -> error
    end
  end

  defp normalize_transfer(%{"amount" => amount, "iban" => iban, "name" => name, "reference" => reference}) do
    iban = normalize_iban(iban)

    cond do
      not Regex.match?(~r/\A\d+(\.\d{1,2})?\z/, String.trim(amount)) or
          Decimal.compare(Decimal.new(String.trim(amount)), 0) != :gt ->
        {:error, "amount must be a positive EUR amount with at most two decimals, for example 1713.60."}

      not valid_iban?(iban) ->
        {:error, "IBAN #{iban} fails the IBAN checksum. Check it against the invoice."}

      String.trim(name) == "" or String.length(name) > 140 ->
        {:error, "name must be 1 to 140 characters."}

      String.trim(reference) == "" or String.length(reference) > 140 ->
        {:error, "reference must be 1 to 140 characters."}

      true ->
        {:ok, %{amount: String.trim(amount), iban: iban, name: String.trim(name), reference: String.trim(reference)}}
    end
  end

  defp normalize_transfer(_transfer), do: {:error, "amount, iban, name, and reference are required."}

  defp normalize_date(nil), do: {:ok, nil}

  defp normalize_date(value) do
    case Date.from_iso8601(value) do
      {:ok, date} -> {:ok, Date.to_iso8601(date)}
      {:error, _reason} -> {:error, "scheduled_date must be YYYY-MM-DD, for example 2026-11-30."}
    end
  end

  defp normalize_iban(iban), do: iban |> String.replace(~r/\s+/, "") |> String.upcase()

  defp valid_iban?(iban) do
    if Regex.match?(~r/\A[A-Z]{2}\d{2}[A-Z0-9]{11,30}\z/, iban) do
      {head, tail} = String.split_at(iban, 4)

      (tail <> head)
      |> String.to_charlist()
      |> Enum.map_join(fn
        char when char in ?A..?Z -> Integer.to_string(char - ?A + 10)
        char -> <<char>>
      end)
      |> String.to_integer()
      |> rem(97) == 1
    else
      false
    end
  end
end

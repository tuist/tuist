max_transfer_amount = "80000.00"

defmodule Atlas.MCP.Tools.FinanceCreateTransferRequest do
  @moduledoc """
  Prepares outgoing SEPA payments as one pending transfer request in Qonto.
  Nothing is paid until a member with review rights approves the request in
  Qonto with strong customer authentication.

  It only pays IBANs that a completed outgoing Qonto transfer already paid.
  The amount, IBAN, and name usually come from an email or invoice the agent
  read, so a fake "our bank details changed" email could otherwise slip the
  sender's IBAN under a real vendor's name. Qonto lets Owners and Admins
  approve their own requests unless a 4-eye policy is configured, so that
  approval is not a second person by default. A new beneficiary is paid the
  first time in Qonto itself, after its details are checked with the vendor.

  Each transfer is also capped at #{max_transfer_amount} EUR, which bounds
  what one wrong amount from a forged or misread invoice can cost even when
  the beneficiary is known. Larger payments are made in Qonto directly.
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
  alias Atlas.Finance
  alias Atlas.Finance.Config
  alias Atlas.Finance.Providers.Qonto
  alias Atlas.MCP.Tool

  @max_transfer_amount max_transfer_amount

  @scopes ["request_transfers.write"]

  @impl EMCP.Tool
  def description do
    "Prepare outgoing EUR SEPA payments as one pending transfer request in Qonto, for example to pay vendor invoices. Each transfer is at most #{@max_transfer_amount} EUR. Only IBANs Tuist has already paid from Qonto are accepted; a new beneficiary or changed bank details must be checked with the vendor and paid once in Qonto directly. Nothing is paid until someone with review rights approves the request in Qonto with strong customer authentication. Retrying the same request does not create a duplicate. Requires the finance:write scope and the caller's own Qonto connection in Atlas settings (Connections)."
  end

  def execute(conn, %{"source_key" => source_key, "note" => note, "transfers" => transfers} = args) do
    with :ok <- Tool.authorize_scope(conn, "finance:write", "Finance tools"),
         {:ok, source} <- fetch_qonto_source(source_key),
         {:ok, transfers} <- normalize_transfers(transfers),
         :ok <- ensure_paid_before(transfers),
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
              "transfers" => Enum.map(transfers, &Map.take(&1, [:name, :iban, :amount, :reference]))
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
      (amount_error = amount_error(String.trim(amount))) != nil ->
        {:error, amount_error}

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

  defp amount_error(amount) do
    cond do
      not Regex.match?(~r/\A\d+(\.\d{1,2})?\z/, amount) or Decimal.compare(Decimal.new(amount), 0) != :gt ->
        "amount must be a positive EUR amount with at most two decimals, for example 1713.60."

      Decimal.compare(Decimal.new(amount), Decimal.new(@max_transfer_amount)) == :gt ->
        "amount #{amount} is above the #{@max_transfer_amount} EUR limit per transfer. Make payments this large directly in Qonto."

      true ->
        nil
    end
  end

  defp ensure_paid_before(transfers) do
    paid = transfers |> Enum.map(& &1.iban) |> Enum.uniq() |> Finance.paid_ibans()

    transfers
    |> Enum.with_index()
    |> Enum.reject(fn {transfer, _index} -> transfer.iban in paid end)
    |> case do
      [] ->
        :ok

      unpaid ->
        list =
          Enum.map_join(unpaid, ", ", fn {transfer, index} ->
            "transfers[#{index}] #{transfer.iban} (#{transfer.name})"
          end)

        {:error,
         "Tuist has never paid these IBANs from Qonto, so Atlas will not request payment to them: #{list}. " <>
           "Bank details in an email or invoice can be forged. Ask the person you're working for to confirm the details " <>
           "with the vendor through a channel they already trust, not the message that contained them, and make this " <>
           "first payment directly in Qonto. Once it has settled and synced, Atlas can request later payments to that IBAN."}
    end
  end

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

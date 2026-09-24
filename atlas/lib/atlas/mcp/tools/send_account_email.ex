defmodule Atlas.MCP.Tools.SendAccountEmail do
  @moduledoc """
  Sends one transactional email to one recipient, addressed either directly or
  through the account whose billing contact should receive it.
  """

  use Atlas.MCP.Tool,
    name: "send_account_email",
    schema: %{
      "type" => "object",
      "description" =>
        "Provide either email, or one of account_id, account_key, or handle to address the account's billing contact.",
      "required" => ["subject", "body_markdown"],
      "properties" =>
        Map.merge(Atlas.MCP.AccountLookup.identifier_schema_properties(), %{
          "email" => %{
            "type" => "string",
            "description" => "Recipient address. Takes precedence over the account identifiers."
          },
          "recipient_name" => %{"type" => "string"},
          "subject" => %{"type" => "string"},
          "body_markdown" => %{"type" => "string"},
          "from_name" => %{"type" => "string"},
          "from_email" => %{"type" => "string"},
          "reply_to_email" => %{"type" => "string"}
        })
    },
    output_schema: %{
      "type" => "object",
      "properties" => %{
        "delivery" => Atlas.MCP.Serializers.GTMEmail.delivery_schema(),
        "duplicate" => %{"type" => "boolean"}
      },
      "required" => ["delivery", "duplicate"],
      "additionalProperties" => false
    }

  alias Atlas.Accounts.Account
  alias Atlas.GTM
  alias Atlas.MCP.AccountLookup
  alias Atlas.MCP.Serializers.GTMEmail
  alias Atlas.MCP.Tool

  @account_identifiers ~w(account_id account_key handle)

  @impl EMCP.Tool
  def description do
    "Send a single transactional email to one recipient, such as a billing, pricing, or contract notice. Unlike send_email_broadcast this carries no unsubscribe footer and ignores subscriber status, so a recipient who left a marketing audience still receives it. Only call it when the user explicitly asks to send, because it queues delivery immediately."
  end

  def execute(conn, args) do
    with {:ok, recipient_email, account} <- resolve_recipient(args),
         attrs =
           args
           |> Map.take(~w(recipient_name subject body_markdown from_name from_email reply_to_email))
           |> Map.merge(%{"recipient_email" => recipient_email, "account" => account}),
         {:ok, result} <- GTM.queue_direct_email(attrs, Tool.current_user(conn)) do
      {:ok, %{delivery: GTMEmail.delivery(result.delivery), duplicate: result.duplicate}}
    else
      {:error, {:invalid, field, message}} ->
        {:error, "Could not queue email: #{field} #{message}."}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:error, "Could not queue email: #{Tool.format_changeset_errors(changeset)}"}

      {:error, reason} when is_binary(reason) ->
        {:error, reason}

      {:error, reason} ->
        {:error, "Could not queue email: #{inspect(reason)}"}
    end
  end

  defp resolve_recipient(%{"email" => email} = args) when is_binary(email) and email != "" do
    case account_identifiers(args) do
      %{} = identifiers when map_size(identifiers) > 0 ->
        with {:ok, account} <- AccountLookup.resolve(identifiers), do: {:ok, email, account}

      _identifiers ->
        {:ok, email, nil}
    end
  end

  defp resolve_recipient(args) do
    case account_identifiers(args) do
      %{} = identifiers when map_size(identifiers) > 0 ->
        with {:ok, account} <- AccountLookup.resolve(identifiers),
             {:ok, email} <- billing_email(account) do
          {:ok, email, account}
        end

      _identifiers ->
        {:error, "Provide email, or one of account_id, account_key, or handle."}
    end
  end

  defp account_identifiers(args) do
    args
    |> Map.take(@account_identifiers)
    |> Map.filter(fn {_key, value} -> is_binary(value) and value != "" end)
  end

  # Contractual mail goes to the contact the account nominated for it. Anything
  # else would be a guess about who is entitled to a price or contract notice,
  # so the caller is asked for the address instead.
  defp billing_email(%Account{billing: %{email: email}}) when is_binary(email) and email != "" do
    {:ok, email}
  end

  defp billing_email(%Account{} = account) do
    {:error, "Account #{account.account_key} has no billing email. Pass email explicitly to choose the recipient."}
  end
end

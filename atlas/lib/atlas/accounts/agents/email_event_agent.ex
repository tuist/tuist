defmodule Atlas.Accounts.Agents.EmailEventAgent do
  @moduledoc """
  Processes an inbound email end-to-end via tool calls: finds the matching
  Atlas account and stores the timeline event, instead of returning data for
  the caller to act on.
  """

  use Condukt

  alias Atlas.Agents.Sessions
  alias Atlas.Agents.StyleGuide
  alias Atlas.Inbox
  alias Atlas.Inbox.EmailParser
  alias Atlas.LLMs.Runner

  @impl true
  def tools, do: []

  @doc """
  Runs the agent against a parsed email struct.

  Returns `{:ok, %{status: "captured", event_id: id}}`,
  `{:ok, %{status: "ignored", reason: reason}}`, or `{:error, reason}`.
  """
  def run(email) do
    with {:ok, llm} <- Runner.fetch_config() do
      tools = [
        find_account_tool(),
        list_contacts_tool(),
        upsert_contact_tool(),
        store_event_tool(email)
      ]

      Sessions.run(
        __MODULE__,
        build_prompt(email),
        Runner.client_opts(llm) ++
          [
            tools: tools,
            load_project_instructions: false,
            max_turns: 15,
            output: output_schema()
          ]
      )
    end
  end

  defp find_account_tool do
    Condukt.tool(
      name: "find_account",
      description: """
      Find the Atlas account that owns this email conversation.
      Pass all participant email addresses; the server filters internal addresses
      and tries to match by contact email, account handle, and primary domain.
      Returns blocked: true when the identifiers match an account that was
      explicitly marked as not an account. In that case, ignore the email.
      Returns {"found": false} when no account matches.
      """,
      parameters: %{
        type: "object",
        properties: %{
          emails: %{
            type: "array",
            items: %{type: "string"},
            description: "All participant email addresses from the conversation"
          }
        },
        required: ["emails"]
      },
      call: fn %{"emails" => emails}, ctx ->
        case Inbox.find_non_account(emails) do
          %{account: account, matched_on: matched_on} ->
            {:ok,
             %{
               found: false,
               blocked: true,
               reason: "not_account",
               account: account_response(account),
               matched_on: matched_on
             }, %{blocked_non_account: true}}

          nil ->
            case Inbox.find_account(emails) do
              nil ->
                {:ok, %{found: false, blocked: false}}

              %{account: account, matched_on: matched_on} ->
                if session_id = Map.get(ctx, :session_id) do
                  Sessions.attach_account(session_id, account.id)
                end

                {:ok,
                 %{
                   found: true,
                   blocked: false,
                   account: account_response(account),
                   matched_on: matched_on
                 }, %{found_account_id: account.id}}
            end
        end
      end
    )
  end

  defp list_contacts_tool do
    Condukt.tool(
      name: "list_account_contacts",
      description:
        "List existing contacts for the matched account. Call after find_account so you know who already exists before upserting.",
      parameters: %{
        type: "object",
        properties: %{
          account_id: %{type: "string", description: "account.id from find_account"}
        },
        required: ["account_id"]
      },
      call: fn %{"account_id" => account_id}, ctx ->
        if ctx.assigns[:blocked_non_account] do
          {:error, "matched identifiers are marked as not an account; submit ignored with reason not_account"}
        else
          contacts =
            Inbox.list_account_contacts(account_id)
            |> Enum.map(fn c ->
              %{id: c.id, email: c.email, full_name: c.full_name, title: c.title, notes: c.notes}
            end)

          {:ok, %{contacts: contacts}}
        end
      end
    )
  end

  defp upsert_contact_tool do
    Condukt.tool(
      name: "upsert_contact",
      description: """
      Create or update a contact for the matched account.
      Call for each external participant (skip atlas.tuist.dev addresses).
      For existing contacts, build on their current notes rather than discarding them.
      """,
      parameters: %{
        type: "object",
        properties: %{
          account_id: %{type: "string", description: "account.id from find_account"},
          email: %{type: "string"},
          full_name: %{type: "string", description: "Person's name; use the email local part if no name is available"},
          title: %{type: "string", description: "Job title or role if apparent from the email"},
          notes: %{
            type: "string",
            description: """
            Sales-relevant context: apparent role, personality, tone, decision-making style,
            topics they own, commercial or technical signals, relationship notes.
            For existing contacts, incorporate their current notes and add new insights.
            Omit if there is nothing meaningful to say.
            """
          }
        },
        required: ["account_id", "email", "full_name"]
      },
      call: fn %{"account_id" => account_id} = params, ctx ->
        if ctx.assigns[:blocked_non_account] do
          {:error, "matched identifiers are marked as not an account; submit ignored with reason not_account"}
        else
          case Inbox.upsert_contact(account_id, params) do
            {:ok, :skipped} -> {:ok, %{skipped: true}}
            {:ok, contact} -> {:ok, %{contact_id: contact.id}}
            {:error, reason} -> {:error, inspect(reason)}
          end
        end
      end
    )
  end

  defp store_event_tool(email) do
    Condukt.tool(
      name: "store_email_event",
      description:
        "Persist the email as a timeline event for the matched account. Call only after find_account succeeds.",
      parameters: %{
        type: "object",
        properties: %{
          account_id: %{type: "string", description: "account.id from find_account"},
          title: %{type: "string", description: "Short event title, max 100 characters"},
          summary: %{type: "string", description: "2-4 factual sentences about what happened and why it matters"},
          markdown: %{
            type: "string",
            description: "Concise Markdown: participants, date, asks, commitments, blockers, follow-ups"
          },
          participants: %{
            type: "array",
            items: %{
              type: "object",
              properties: %{
                email: %{type: "string"},
                name: %{type: "string"},
                role: %{type: "string"}
              }
            },
            description: "People or inboxes involved"
          },
          occurred_at: %{type: "string", description: "ISO 8601 timestamp for the conversation"},
          matched_on: %{type: "object", description: "matched_on map from find_account"}
        },
        required: ["account_id", "title", "summary"]
      },
      call: fn params, ctx ->
        found_account_id = ctx.assigns[:found_account_id]

        cond do
          ctx.assigns[:blocked_non_account] ->
            {:error, "matched identifiers are marked as not an account; submit ignored with reason not_account"}

          found_account_id && params["account_id"] != found_account_id ->
            {:error, "account_id mismatch - use the account_id returned by find_account"}

          true ->
            case Inbox.store_email_event(email, params) do
              {:ok, event} ->
                {:ok, %{event_id: event.id, account_id: event.account_id}, %{stored_event_id: event.id}}

              {:error, reason} ->
                {:error, inspect(reason)}
            end
        end
      end
    )
  end

  @impl true
  def system_prompt do
    """
    You process inbound customer emails for an account management workspace.

    Steps:
    1. Call find_account with all participant email addresses.
    2. If find_account returns blocked: true, submit
       {"status": "ignored", "reason": "not_account"}.
    3. If the email is not about Tuist acting as the service provider to the
       external company, submit {"status": "ignored", "reason": "not_account"}.
       Reject vendor, supplier, partner, tool, support, or procurement
       conversations where the external company provides services to Tuist or
       Tuist is the buyer, even if find_account matched a company domain.
    4. If no account is found, submit {"status": "ignored", "reason": "no_matching_account"}.
    5. If an account is found:
       a. Call list_account_contacts to see who already exists for this account.
       b. For each external participant (skip atlas.tuist.dev addresses), call upsert_contact:
          - full_name: from the email name field, or the email local part if no name is present
          - title: their apparent job title or role if visible in the email
          - notes: sales-relevant context such as role, personality, tone, decision-making style,
            topics they own, commercial or technical signals, relationship observations.
            For existing contacts, incorporate their current notes and layer in new insights.
            Omit notes if there is nothing meaningful to say.
       c. Call store_email_event with:
          - account_id: from find_account
          - title: concise event title, max 100 characters
          - summary: 2-4 factual sentences covering what happened and why it matters
          - markdown: Markdown with participants, date, concrete asks, commitments,
            blockers, commercial signals, and follow-ups when present
          - participants: list of people involved with email, name, role
          - occurred_at: ISO 8601 timestamp from the email date header
          - matched_on: the matched_on value from find_account
       d. Preserve concrete commitments, owners, and dates in the timeline event.
          Do not turn them into a separate task list.
       e. Submit {"status": "captured", "event_id": from store_email_event, "account_id": from find_account}.

    Stay grounded in the email. Do not invent names, dates, blockers, roles, or next steps.
    If the email is sparse, say so plainly and keep notes brief.

    #{StyleGuide.prose_rules()}
    """
  end

  defp output_schema do
    %{
      type: "object",
      properties: %{
        status: %{type: "string", enum: ["captured", "ignored"]},
        event_id: %{type: "string"},
        account_id: %{type: "string"},
        reason: %{type: "string"}
      },
      required: [:status]
    }
  end

  defp build_prompt(email) do
    "Process this inbound email.\n\n#{JSON.encode!(EmailParser.to_agent_context(email))}"
  end

  defp account_response(account) do
    %{
      id: account.id,
      name: account.name,
      segment: account.segment && Atom.to_string(account.segment),
      primary_domain: account.primary_domain,
      description: account.description,
      deal_stage: account.deal_stage
    }
  end
end

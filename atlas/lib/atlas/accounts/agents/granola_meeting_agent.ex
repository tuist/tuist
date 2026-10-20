defmodule Atlas.Accounts.Agents.GranolaMeetingAgent do
  @moduledoc """
  Routes a Granola meeting note to an account and stores it as an event.
  """

  alias Atlas.Accounts.EventRouting
  alias Atlas.Agents.StyleGuide
  alias Atlas.Granola
  alias Atlas.Granola.Note
  alias Atlas.LLMs.Runner

  @doc """
  Runs the agent against a normalized Granola note.

  Returns `{:ok, %{status: "captured", event_id: id, account_id: id}}`,
  `{:ok, %{status: "ignored", reason: reason}}`, or `{:error, reason}`.
  """
  def run(%Note{} = note) do
    with {:ok, llm} <- Runner.fetch_config() do
      tools = [
        find_account_tool(),
        upsert_account_tool(),
        list_contacts_tool(),
        upsert_contact_tool(),
        store_event_tool(note)
      ]

      Condukt.run(
        build_prompt(note),
        Runner.client_opts(llm) ++
          [
            system_prompt: system_prompt(),
            tools: tools,
            load_project_instructions: false,
            max_turns: 15,
            output: output_schema()
          ]
      )
    end
  end

  def system_prompt do
    """
    You process Granola customer meeting notes for an account management workspace.

    Steps:
    1. Call find_account with every participant email from the note: attendees,
       calendar invitees, organizer, and owner.
    2. If find_account returns blocked: true, submit
       {"status": "ignored", "reason": "not_account"}.
    3. If all non-internal participants are from Tuist or Atlas, submit
       {"status": "ignored", "reason": "internal_meeting"}.
    4. If the note is not about Tuist acting as the service provider to the
       external company, submit {"status": "ignored", "reason": "not_account"}.
       Reject vendor, supplier, partner, tool, support, or procurement
       conversations where the external company provides services to Tuist or
       Tuist is the buyer, even if find_account matched a company domain.
    5. If no account is found, call upsert_account only when the note clearly
       shows we are talking with that company about their usage of Tuist:
       evaluating Tuist, using Tuist, trialing Tuist, getting Tuist support, or
       discussing commercial terms for Tuist. The domain must represent that
       company in the Tuist-usage conversation. A company name, domain, or work
       email domain alone is not enough. Do not create accounts for incidental
       company mentions, vendors, tools, employers, conference/event attendees,
       hiring conversations, partnerships, generic OSS discussions, or other
       meetings where Tuist usage is not being discussed. Create it as a lead
       by default unless the note clearly shows an active trial or customer
       relationship. If this Tuist-usage signal is unclear, submit
       {"status": "ignored", "reason": "no_matching_account"}.
    6. If an account is found, or after upsert_account creates one:
       a. If the note provides reliable account-level information, call
          upsert_account with account_id to update the existing account. Do not
          overwrite account fields with guesses or one-off meeting phrasing.
       b. Call list_account_contacts to see who already exists for this account.
       c. For each external attendee or invitee, call upsert_contact:
          - full_name: from the Granola attendee name, or the email local part
          - title: apparent job title or role if visible in the notes
          - notes: sales-relevant context from the meeting only. For existing
            contacts, incorporate current notes and add new insights.
       d. Call store_granola_meeting_event with:
          - account_id: from find_account or upsert_account
          - title: concise meeting title, max 100 characters
          - summary: 1-3 factual sentences about what happened and why it matters
          - markdown: the meeting notes Markdown to store; prefer Granola's
            summary_markdown content and do not invent sections
          - participants: people involved in the meeting, name, role
          - occurred_at: calendar_event.scheduled_start_time when present,
            otherwise note.created_at
          - matched_on: the matched_on value from find_account
       e. Preserve concrete commitments, owners, and dates in the timeline event.
          Do not turn them into a separate task list.
       f. Submit {"status": "captured", "event_id": from store_granola_meeting_event, "account_id": from find_account or upsert_account}.

    Stay grounded in the Granola note. Do not invent names, dates, blockers,
    commitments, or follow-ups.

    #{StyleGuide.prose_rules()}
    """
  end

  defp find_account_tool do
    Condukt.tool(
      name: "find_account",
      description: """
      Find the Atlas account that owns this Granola meeting.
      Pass all participant email addresses; the server filters internal addresses
      and tries to match by contact email, account handle, and primary domain.
      Returns blocked: true when the identifiers match an account that was
      explicitly marked as not an account. In that case, ignore the note.
      Returns {"found": false} when no account matches.
      """,
      parameters: %{
        type: "object",
        properties: %{
          emails: %{
            type: "array",
            items: %{type: "string"},
            description: "All participant email addresses from the meeting"
          }
        },
        required: ["emails"]
      },
      call: fn %{"emails" => emails}, _ctx ->
        case EventRouting.find_non_account(emails) do
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
            case EventRouting.find_account(emails) do
              nil ->
                {:ok, %{found: false, blocked: false}}

              %{account: account, matched_on: matched_on} ->
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

  defp upsert_account_tool do
    Condukt.tool(
      name: "upsert_account",
      description: """
      Create a new Atlas account when no account matches the meeting, or update
      reliable account-level fields for an existing account.
      For updates, pass account_id from find_account or a previous upsert_account
      response. For creates, omit account_id and provide at least name plus
      tuist_usage_signal. Only create when the meeting is with that company
      about its usage, evaluation, support needs, trial, or commercial terms for
      Tuist. Include primary_domain only when the domain belongs to that company.
      """,
      parameters: %{
        type: "object",
        properties: %{
          account_id: %{
            type: "string",
            description: "Existing account.id from find_account or a previous upsert_account response"
          },
          name: %{type: "string", description: "Company or account name"},
          primary_domain: %{
            type: "string",
            description: "Company domain for the organization discussing its Tuist usage"
          },
          tuist_usage_signal: %{
            type: "string",
            description:
              "Required for creates: concise evidence from the note that this company is discussing its Tuist usage, evaluation, support needs, trial, or commercial terms"
          },
          url: %{type: "string", description: "Company website URL, if explicit"},
          description: %{type: "string", description: "Stable account-level context grounded in the note"},
          segment: %{
            type: "string",
            enum: ["lead", "prospect", "customer"],
            description:
              "Use lead by default; prospect for active trials or qualified opportunities; customer only when clear."
          },
          deal_stage: %{type: "string", description: "Known account deal stage only when explicit"}
        }
      },
      call: fn params, ctx ->
        with :ok <- validate_upsert_account_request(params, ctx.assigns),
             {:ok, account} <- EventRouting.upsert_account(params) do
          {:ok, %{account: account_response(account), created_or_updated: true}, %{found_account_id: account.id}}
        else
          {:error, reason} when is_binary(reason) ->
            {:error, reason}

          {:error, reason} ->
            {:error, inspect(reason)}
        end
      end
    )
  end

  defp validate_upsert_account_request(params, assigns) do
    found_account_id = assigns[:found_account_id]
    account_id = params["account_id"]

    cond do
      assigns[:blocked_non_account] ->
        {:error, "matched identifiers are marked as not an account; submit ignored with reason not_account"}

      found_account_id && account_id && account_id != found_account_id ->
        {:error, "account_id mismatch - use the account_id returned by find_account or upsert_account"}

      requires_account_creation_signal?(found_account_id, account_id) && missing_tuist_usage_signal?(params) ->
        {:error,
         "tuist_usage_signal is required when creating an account without an existing match; only create accounts for companies discussing their usage of Tuist"}

      true ->
        :ok
    end
  end

  defp requires_account_creation_signal?(nil, account_id), do: blank?(account_id)
  defp requires_account_creation_signal?(_found_account_id, _account_id), do: false

  defp missing_tuist_usage_signal?(params) do
    params
    |> Map.get("tuist_usage_signal")
    |> blank?()
  end

  defp blank?(value), do: is_nil(value) or (is_binary(value) and String.trim(value) == "")

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
            EventRouting.list_account_contacts(account_id)
            |> Enum.map(fn contact ->
              %{
                id: contact.id,
                email: contact.email,
                full_name: contact.full_name,
                title: contact.title,
                notes: contact.notes
              }
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
      Call for each external meeting participant. The server skips internal addresses.
      For existing contacts, build on their current notes rather than discarding them.
      """,
      parameters: %{
        type: "object",
        properties: %{
          account_id: %{type: "string", description: "account.id from find_account"},
          email: %{type: "string"},
          full_name: %{type: "string", description: "Person's name; use the email local part if no name is available"},
          title: %{type: "string", description: "Job title or role if apparent from the meeting"},
          notes: %{
            type: "string",
            description: """
            Sales-relevant context: apparent role, decision-making style, topics
            they own, commercial or technical signals, relationship notes.
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
          case EventRouting.upsert_contact(account_id, params) do
            {:ok, :skipped} -> {:ok, %{skipped: true}}
            {:ok, contact} -> {:ok, %{contact_id: contact.id}}
            {:error, reason} -> {:error, inspect(reason)}
          end
        end
      end
    )
  end

  defp store_event_tool(note) do
    Condukt.tool(
      name: "store_granola_meeting_event",
      description:
        "Persist the Granola note as a meeting timeline event for the matched account. Call only after find_account or upsert_account succeeds.",
      parameters: %{
        type: "object",
        properties: %{
          account_id: %{type: "string", description: "account.id from find_account"},
          title: %{type: "string", description: "Short meeting title, max 100 characters"},
          summary: %{type: "string", description: "1-3 factual sentences about what happened and why it matters"},
          markdown: %{
            type: "string",
            description: "Meeting notes in Markdown. Prefer the Granola summary_markdown content."
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
            description: "People involved in the meeting"
          },
          occurred_at: %{type: "string", description: "ISO 8601 meeting timestamp"},
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
            case Granola.store_meeting_event(note, params) do
              {:ok, event} ->
                {:ok, %{event_id: event.id, account_id: event.account_id}, %{stored_event_id: event.id}}

              {:error, reason} ->
                {:error, inspect(reason)}
            end
        end
      end
    )
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

  defp build_prompt(%Note{} = note) do
    "Process this Granola meeting note.\n\n#{JSON.encode!(Note.to_agent_context(note))}"
  end

  defp account_response(account) do
    %{
      id: account.id,
      name: account.name,
      segment: account.segment && Atom.to_string(account.segment),
      primary_domain: account.primary_domain,
      url: account.url,
      description: account.description,
      deal_stage: account.deal_stage
    }
  end
end

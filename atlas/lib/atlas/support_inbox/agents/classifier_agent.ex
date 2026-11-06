defmodule Atlas.SupportInbox.Agents.ClassifierAgent do
  @moduledoc """
  Single-turn Condukt agent that classifies an inbound email to
  `contact@tuist.dev` so the notifier can decide whether to ping
  `#support` (a human must act) or silence the email (routine
  vendor traffic that only needs to be filed).

  The agent returns a structured decision:

    * `category` — the coarse bucket the email falls into.
    * `action_needed` — true when a human must reply, decide, or
      intervene; false when the email is routine (invoice, shipping
      update, publish confirmation).
    * `urgency` — how quickly action is required (`:high` for
      service warnings, `:none` for routine records).
    * `confidence` — model's stated confidence in the decision; the
      caller falls back to `#support` for low-confidence decisions
      so a mis-classified support thread is never silently dropped.
    * `reason` — a short line the notifier surfaces alongside the
      Slack post, so a wrong classification is visible at a glance.

  Two read-only tools give the agent the state it needs to make a
  good call:

    * `find_open_support_thread` — is there already a live thread
      from this sender? Live conversations should always ping.
    * `find_finance_transaction` — does the invoice number or
      amount match a recorded finance transaction? Matched invoices
      are safe to file silently.
  """

  use Condukt

  alias Atlas.Agents.Sessions
  alias Atlas.Agents.StyleGuide
  alias Atlas.Finance
  alias Atlas.LLMs.Runner
  alias Atlas.Support

  @categories ~w(support invoice vendor_notice shipping publish registration ar spam other)a
  @urgencies ~w(none low normal high)a

  @body_char_limit 4_000

  @impl true
  def tools do
    [find_open_support_thread_tool(nil), find_finance_transaction_tool()]
  end

  @impl true
  def system_prompt do
    """
    You classify an inbound email sent to Tuist's shared address
    `contact@tuist.dev` so the notifier can route it correctly.
    The address receives real customer support alongside vendor
    invoices, shipping updates, package-publish confirmations, and
    dubious cold outreach. Only a small share of the volume needs a
    human to reply.

    For each email, return exactly one of these categories:

      - support: a customer, prospect, or applicant asking a
        question, reporting a bug, or continuing a real conversation.
      - invoice: a vendor invoice or receipt to file (Hetzner,
        Cloudflare, DeepL, hardware suppliers, etc.).
      - vendor_notice: a transactional message from a vendor about
        an account, service, or order. Some are routine (soft
        reboots, order confirmations); others require action
        (billing alerts, traffic warnings, plan cancellations,
        bank-account-change verifications, vendor questions about
        a specific order).
      - shipping: delivery, tracking, or dispatch update.
      - publish: package or plugin publish confirmation (Hex.pm,
        RubyGems, Gradle plugin portal).
      - registration: account-creation, verification code, or
        activation email.
      - ar: accounts-receivable notification about an invoice
        Tuist sent or a payout Tuist received.
      - spam: cold outreach, guest-post pitches, or unsolicited
        opportunities.
      - other: fallback for anything the categories above miss.

    Then decide `action_needed` and `urgency`:

      - action_needed=true when a human on the team must reply,
        decide, or intervene. Support emails are always
        action_needed=true. Vendor notices are action_needed=true
        only when there is something to do (billing alert,
        service warning, plan cancellation, bank-change
        verification, vendor question about our order).
      - action_needed=false for routine records that only need to
        be filed (invoices, shipping updates, publish
        confirmations, order confirmations, registrations, AR
        notifications, spam).

      - urgency=high: service is at risk (traffic warning,
        suspension notice, security incident, customer reporting
        production breakage).
      - urgency=normal: needs a reply within a business day
        (support question, sales inquiry, vendor question about
        an order).
      - urgency=low: worth a human eye but not time-sensitive
        (internship application, generic feedback).
      - urgency=none: no action required.

    Rules of thumb:

      - Prefer using the tools over guessing. If the sender has an
        open support thread, this email is almost certainly
        support and action_needed=true regardless of subject.
      - A Hetzner invoice email with a matching finance
        transaction is safe to file silently. Without a match, it
        is still an invoice, just log the miss in `reason`.
      - Never mark a first-time email from a real person at a
        company domain as spam. Only obviously templated pitches
        (guest posts, SEO offers, "collaboration opportunity")
        count as spam.
      - If you are unsure, prefer action_needed=true with lower
        confidence — a wrongly-notified email is cheap, a
        silently-swallowed support thread is not.

    `confidence` is your own confidence in the decision on a
    0.0–1.0 scale. `reason` is one short sentence the notifier
    will show next to the Slack post.

    #{StyleGuide.prose_rules()}
    """
  end

  @doc """
  Classifies the inbound email. `input` is a map with at least
  `:from`, `:subject`, and optionally `:body` and
  `:exclude_thread_id`. The last one is the thread this inbound
  was ingested into — the `find_open_support_thread` tool filters
  it out so the classifier doesn't see the just-created thread
  when it asks "does this sender have a live conversation?".

  Returns `{:ok, decision}` where `decision` is a map with atom
  keys `:category`, `:action_needed`, `:urgency`, `:confidence`,
  `:reason`, or `{:error, reason}` when the LLM is unavailable or
  refuses to answer.
  """
  def classify(input) when is_map(input) do
    case Runner.fetch_config() do
      {:ok, llm} ->
        Sessions.run(
          __MODULE__,
          prompt(input),
          Runner.client_opts(llm) ++
            [
              max_turns: 4,
              load_project_instructions: false,
              output: output_schema(),
              tools: [
                find_open_support_thread_tool(input[:exclude_thread_id]),
                find_finance_transaction_tool()
              ]
            ]
        )
        |> normalize()

      {:error, :llm_not_configured} = error ->
        error
    end
  end

  defp prompt(input) do
    """
    Classify this inbound email:

    From: #{input[:from] || "(unknown sender)"}
    Subject: #{input[:subject] || "(no subject)"}

    Body (first #{@body_char_limit} characters):
    #{truncate(input[:body], @body_char_limit)}

    Use the tools to check whether the sender already has an open
    support thread and whether an invoice number or amount in the
    email matches a recorded finance transaction before deciding.
    """
  end

  defp truncate(nil, _limit), do: "(body not available)"
  defp truncate(body, limit) when is_binary(body), do: String.slice(body, 0, limit)

  defp output_schema do
    %{
      type: "object",
      required: ["category", "action_needed", "urgency", "confidence", "reason"],
      properties: %{
        category: %{type: "string", enum: Enum.map(@categories, &Atom.to_string/1)},
        action_needed: %{type: "boolean"},
        urgency: %{type: "string", enum: Enum.map(@urgencies, &Atom.to_string/1)},
        confidence: %{type: "number", minimum: 0.0, maximum: 1.0},
        reason: %{type: "string", maxLength: 400}
      }
    }
  end

  defp normalize({:ok, result}) when is_map(result) do
    result = Map.new(result, fn {key, value} -> {to_string(key), value} end)

    with {:ok, category} <- fetch_enum(result, "category", @categories),
         {:ok, urgency} <- fetch_enum(result, "urgency", @urgencies),
         {:ok, action_needed} <- fetch_boolean(result, "action_needed"),
         {:ok, confidence} <- fetch_confidence(result),
         {:ok, reason} <- fetch_reason(result) do
      {:ok,
       %{
         category: category,
         action_needed: action_needed,
         urgency: urgency,
         confidence: confidence,
         reason: reason
       }}
    end
  end

  defp normalize({:ok, _other}), do: {:error, :invalid_classifier_output}
  defp normalize({:error, _reason} = error), do: error

  defp fetch_enum(map, key, allowed) do
    case Map.get(map, key) do
      value when is_binary(value) ->
        case Enum.find(allowed, &(Atom.to_string(&1) == value)) do
          nil -> {:error, {:invalid_enum, key, value}}
          value -> {:ok, value}
        end

      _other ->
        {:error, {:missing_field, key}}
    end
  end

  defp fetch_boolean(map, key) do
    case Map.get(map, key) do
      value when is_boolean(value) -> {:ok, value}
      _other -> {:error, {:missing_field, key}}
    end
  end

  defp fetch_confidence(map) do
    case Map.get(map, "confidence") do
      value when is_number(value) and value >= 0.0 and value <= 1.0 -> {:ok, value * 1.0}
      _other -> {:error, {:missing_field, "confidence"}}
    end
  end

  defp fetch_reason(map) do
    case Map.get(map, "reason") do
      value when is_binary(value) -> {:ok, String.trim(value)}
      _other -> {:ok, ""}
    end
  end

  defp find_open_support_thread_tool(exclude_thread_id) do
    Condukt.tool(
      name: "find_open_support_thread",
      description: """
      Return any open or waiting support thread from the given
      sender email, excluding the thread this inbound was ingested
      into. Use before deciding: a reply from an address with a
      live prior thread is almost always another support message.
      An empty result means this sender has no other live
      conversations, so classify the email on its own merits.
      """,
      parameters: %{
        type: "object",
        required: ["email"],
        properties: %{
          email: %{
            type: "string",
            description: "The sender email address to look up."
          }
        }
      },
      call: fn params, _ctx ->
        email = params |> Map.get("email", "") |> String.downcase() |> String.trim()

        case email do
          "" ->
            {:error, "email is required."}

          email ->
            threads =
              [status: "open", query: email, page_size: 5]
              |> Support.list_threads()
              |> thread_rows()
              |> Enum.concat(
                [status: "waiting", query: email, page_size: 5]
                |> Support.list_threads()
                |> thread_rows()
              )
              |> Enum.uniq_by(& &1.id)
              |> Enum.reject(&excluded?(&1, exclude_thread_id))

            {:ok, %{threads: threads, count: length(threads)}}
        end
      end
    )
  end

  defp excluded?(_thread_row, nil), do: false
  defp excluded?(%{id: id}, id), do: true
  defp excluded?(_thread_row, _exclude_id), do: false

  defp thread_rows({%{entries: threads}, _meta}) when is_list(threads), do: Enum.map(threads, &thread_row/1)
  defp thread_rows({threads, _meta}) when is_list(threads), do: Enum.map(threads, &thread_row/1)
  defp thread_rows(_), do: []

  defp thread_row(thread) do
    %{
      id: thread.id,
      customer_email: thread.customer_email,
      subject: thread.subject,
      status: thread.status,
      last_message_at: iso8601(thread.last_message_at)
    }
  end

  defp find_finance_transaction_tool do
    Condukt.tool(
      name: "find_finance_transaction",
      description: """
      Search recorded finance transactions by a free-text query
      (invoice number, counterparty, description). Returns up to
      five matches. Use to confirm that a vendor invoice has an
      existing transaction, in which case the email is safe to
      file silently.
      """,
      parameters: %{
        type: "object",
        required: ["query"],
        properties: %{
          query: %{
            type: "string",
            description: "Text to match against counterparty, description, or reference."
          }
        }
      },
      call: fn params, _ctx ->
        query = params |> Map.get("query", "") |> String.trim()

        case query do
          "" ->
            {:error, "query is required."}

          query ->
            transactions =
              [query: query, limit: 5]
              |> Finance.list_transactions()
              |> Enum.map(&transaction_row/1)

            {:ok, %{transactions: transactions, count: length(transactions)}}
        end
      end
    )
  end

  defp transaction_row(transaction) do
    %{
      id: transaction.id,
      counterparty: Map.get(transaction, :counterparty_name),
      description: Map.get(transaction, :description),
      reference: Map.get(transaction, :reference),
      amount_cents: Map.get(transaction, :amount_cents),
      currency: Map.get(transaction, :currency),
      occurred_on: date_string(Map.get(transaction, :occurred_on))
    }
  end

  defp iso8601(nil), do: nil
  defp iso8601(%DateTime{} = dt), do: DateTime.to_iso8601(dt)
  defp iso8601(%NaiveDateTime{} = dt), do: dt |> NaiveDateTime.truncate(:second) |> NaiveDateTime.to_iso8601()

  defp date_string(nil), do: nil
  defp date_string(%Date{} = date), do: Date.to_iso8601(date)
end

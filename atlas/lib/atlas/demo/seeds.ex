defmodule Atlas.Demo.Seeds do
  @moduledoc """
  Small, idempotent fictional dataset for the isolated demo, deliberately separate
  from developer seeds. Inserts use schemas directly so no jobs or integrations run.
  """

  alias Atlas.Accounts.Account
  alias Atlas.Accounts.Contact
  alias Atlas.Accounts.Event
  alias Atlas.Accounts.Invoice
  alias Atlas.Accounts.Term
  alias Atlas.Finance.Account, as: BankAccount
  alias Atlas.Finance.Category
  alias Atlas.Finance.Source
  alias Atlas.Finance.Transaction
  alias Atlas.Notes.Note
  alias Atlas.Repo
  alias Atlas.Tasks.Task
  alias Atlas.Users.User

  @tables ~w(users accounts account_contacts account_events account_invoices account_terms tasks notes finance_sources finance_accounts finance_categories finance_transactions)

  def verify! do
    for table <- @tables do
      %{rows: [[foreign_rows?]]} =
        Repo.query!("SELECT EXISTS (SELECT 1 FROM #{table} WHERE id::text NOT LIKE '00000000-0000-4000-8000-%')")

      if foreign_rows?, do: raise("Atlas demo refuses a database containing non-demo records in #{table}")
    end

    :ok
  end

  def run! do
    Repo.transact(fn ->
      Repo.query!("SELECT pg_advisory_xact_lock(hashtextextended('atlas-demo-seeds', 0))")
      verify!()
      today = Date.utc_today()
      now = DateTime.utc_now() |> DateTime.truncate(:second)
      alex = put!(User, "alex", %{name: "Alex Morgan", email: "alex@northstar.example.invalid"})
      robin = put!(User, "robin", %{name: "Robin Chen", email: "robin@northstar.example.invalid"})

      for {key, name, segment, status, value} <- [
            {"helio", "Helio Commerce", :customer, "active", "48000"},
            {"orbit", "Orbit Mobility", :prospect, "trial", "24000"},
            {"lumen", "Lumen Health", :lead, "active", "12000"},
            {"cedar", "Cedar Studio", :customer, "churned", "18000"}
          ] do
        account =
          put!(Account, key, %{
            account_key: "atlas-demo:#{key}",
            name: name,
            segment: segment,
            status: status,
            description: "Fictional #{name} account for the Atlas demo.",
            currency: "EUR",
            current_value: Decimal.new(value),
            contacts_count: 1,
            hosting: "cloud",
            plan_tier: "enterprise",
            next_renewal_date: Date.add(today, 45),
            latest_activity_at: now,
            overview_summary:
              "#{name} is evaluating how its platform team can reduce build times. Alex owns the relationship; the next step is a quarterly review.",
            overview_summary_generated_at: now,
            metadata: %{"source" => "atlas-demo"}
          })

        put!(Contact, "#{key}-contact", %{
          account_id: account.id,
          full_name: "Sam Taylor",
          email: "sam@#{key}.example.invalid",
          title: "Platform lead",
          is_primary: true
        })

        put!(Event, "#{key}-event", %{
          account_id: account.id,
          author_id: alex.id,
          external_id: "atlas-demo:#{key}:review",
          source: "manual",
          kind: "note",
          title: "Platform review",
          body: "The team reviewed build performance and agreed on a follow-up with the platform lead.",
          occurred_at: DateTime.add(now, -2, :day)
        })

        put!(Task, "#{key}-task", %{
          account_id: account.id,
          assignee_id: alex.id,
          created_by_id: robin.id,
          title: "Prepare #{name} quarterly review",
          description: "Review progress, invoices, and the next commercial milestone.",
          due_on: Date.add(today, 7)
        })

        if segment == :customer do
          put!(Term, "#{key}-term", %{
            account_id: account.id,
            source: "manual",
            payment: "yearly",
            start_date: Date.add(today, -320),
            end_date: Date.add(today, 45),
            total: Decimal.new(value),
            currency: "EUR",
            seats: 80
          })

          put!(Invoice, "#{key}-invoice", %{
            account_id: account.id,
            external_id: "atlas-demo:#{key}",
            source: "manual",
            number: "NS-#{key}-001",
            due_date: Date.add(today, 14),
            amount_value: Decimal.new(value),
            amount_currency: "EUR",
            status: "open"
          })
        end
      end

      put!(Note, "operating-principles", %{
        created_by_id: alex.id,
        title: "Northstar operating principles",
        content:
          "# Keep the team connected\n\nWe review commercial accounts weekly, link follow-up tasks to their accounts, and keep decisions in shared notes.\n\nThis company and every record in this demo are fictional.",
        visibility: "authenticated"
      })

      put!(Note, "review-playbook", %{
        created_by_id: robin.id,
        title: "Quarterly account review playbook",
        content:
          "# Account reviews\n\n1. Read the account timeline.\n2. Review commercial terms and outstanding invoices.\n3. Agree on the next milestone.\n4. Assign the follow-up task.",
        visibility: "authenticated"
      })

      seed_finance!(today, now)
      {:ok, :seeded}
    end)
  end

  defp seed_finance!(today, now) do
    source =
      put!(Source, "bank-source", %{
        provider: "demo",
        config_key: "atlas-demo-bank",
        name: "Northstar fictional bank",
        last_successful_sync_at: now,
        metadata: %{"source" => "atlas-demo"}
      })

    bank =
      put!(BankAccount, "bank-account", %{
        finance_source_id: source.id,
        provider: "demo",
        external_id: "atlas-demo-bank",
        name: "Operating account",
        currency: "EUR",
        balance_value: Decimal.new("240000"),
        balance_currency: "EUR",
        available_balance_value: Decimal.new("240000"),
        available_balance_currency: "EUR",
        main: true,
        status: "active",
        refreshed_at: now
      })

    revenue = put!(Category, "revenue", %{name: "Customer revenue", slug: "atlas-demo-revenue", direction: "credit"})

    infrastructure =
      put!(Category, "infrastructure", %{name: "Infrastructure", slug: "atlas-demo-infrastructure", direction: "debit"})

    payroll = put!(Category, "payroll", %{name: "Payroll", slug: "atlas-demo-payroll", direction: "debit"})

    for month <- 0..17,
        {key, name, direction, amount, category} <- [
          {"helio-payment", "Helio Commerce", "credit", "4000", revenue},
          {"cloud", "Nimbus Cloud", "debit", "2300", infrastructure},
          {"payroll", "Northstar team", "debit", "19000", payroll}
        ] do
      month_index = today.year * 12 + today.month - 1 - month
      date = Date.new!(div(month_index, 12), rem(month_index, 12) + 1, 3)
      date = if Date.after?(date, today), do: today, else: date
      booked_at = DateTime.new!(date, ~T[09:00:00], "Etc/UTC")

      put!(Transaction, "#{key}-#{month}", %{
        finance_account_id: bank.id,
        finance_category_id: category.id,
        provider: "demo",
        external_id: "atlas-demo:#{key}:#{month}",
        status: "completed",
        direction: direction,
        counterparty_name: name,
        description: "Fictional monthly #{key} transaction",
        amount_value: Decimal.new(amount),
        amount_currency: "EUR",
        booked_at: booked_at,
        settled_at: booked_at,
        categorized_at: booked_at,
        metadata: %{"source" => "atlas-demo"}
      })
    end
  end

  defp put!(schema, key, attrs) do
    id =
      "00000000-0000-4000-8000-" <>
        binary_part(Base.encode16(:crypto.hash(:sha256, "#{schema}:#{key}"), case: :lower), 0, 12)

    record = Repo.get(schema, id) || struct(schema, id: id)
    record |> Ecto.Changeset.change(attrs) |> Repo.insert_or_update!()
  end
end

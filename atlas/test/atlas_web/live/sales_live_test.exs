defmodule AtlasWeb.SalesLiveTest do
  use AtlasWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias Atlas.Accounts.Account
  alias Atlas.Accounts.Outcome
  alias Atlas.Accounts.OutcomeReview
  alias Atlas.Accounts.Term
  alias Atlas.Repo
  alias Atlas.Stripe.Invoice, as: StripeInvoice
  alias Atlas.TestSupport.StripeClient
  alias Atlas.Users.User

  @tag :skip
  test "renders outcome health and the outcomes needing attention", %{conn: conn} do
    user = insert_user!("sales-overview@example.com")

    off_track_account =
      insert_account!(%{
        account_key: "demo:off-track",
        name: "Off Track Account",
        primary_domain: "off-track.test",
        segment: :prospect
      })

    at_risk_account =
      insert_account!(%{
        account_key: "demo:at-risk",
        name: "At Risk Account",
        segment: :customer
      })

    on_track_account =
      insert_account!(%{
        account_key: "demo:on-track",
        name: "On Track Account",
        segment: :customer
      })

    off_track =
      insert_outcome!(off_track_account, %{
        title: "Complete the security evaluation",
        health: "off_track",
        target: "Written security approval",
        target_date: ~D[2026-07-01]
      })

    at_risk =
      insert_outcome!(at_risk_account, %{
        title: "Reach weekly adoption target",
        health: "at_risk",
        target: "30 weekly active developers",
        target_date: ~D[2026-08-31]
      })

    _on_track =
      insert_outcome!(on_track_account, %{
        title: "Expand to the mobile organization",
        health: "on_track",
        target_date: ~D[2026-09-15]
      })

    insert_review!(off_track, %{
      health: "off_track",
      recommendation: "Run a focused review with both security teams."
    })

    conn = init_test_session(conn, %{"user_id" => user.id})

    {:ok, view, _html} = live(conn, ~p"/sales")

    assert has_element?(view, "#sales")
    assert has_element?(view, "#sales > [data-part='header'] [data-part='title']", "Sales")
    assert has_element?(view, "#sales-widget-on-track [data-part='value']", "1")
    assert has_element?(view, "#sales-widget-at-risk [data-part='value']", "1")
    assert has_element?(view, "#sales-widget-off-track [data-part='value']", "1")
    assert has_element?(view, "#sales-overdue-badge", "1 overdue")

    assert has_element?(
             view,
             "#sales-attention-items-table tr[id='#{off_track.id}']",
             "Complete the security evaluation"
           )

    assert has_element?(
             view,
             "#sales-attention-items-table tr[id='#{off_track.id}']",
             "Run a focused review"
           )

    assert has_element?(
             view,
             "#sales-attention-items-table tr[id='#{at_risk.id}']",
             "Reach weekly adoption target"
           )

    refute has_element?(view, "#sales-attention-items-table", "Expand to the mobile organization")
  end

  @tag :skip
  test "paginates the outcomes needing attention", %{conn: conn} do
    user = insert_user!("sales-attention-pagination@example.com")

    account =
      insert_account!(%{
        account_key: "demo:attention-pagination",
        name: "Pagination Account",
        segment: :prospect
      })

    for index <- 1..13 do
      insert_outcome!(account, %{
        title: "Attention #{String.pad_leading(Integer.to_string(index), 2, "0")}",
        health: "at_risk",
        target_date: Date.add(~D[2026-08-01], index)
      })
    end

    conn = init_test_session(conn, %{"user_id" => user.id})

    {:ok, view, _html} = live(conn, ~p"/sales")

    assert has_element?(view, "[data-part='pagination']")
    assert has_element?(view, "#sales-attention-items-table", "Attention 01")
    refute has_element?(view, "#sales-attention-items-table", "Attention 13")

    view
    |> element("[data-part='pagination'] a", "Next")
    |> render_click()

    assert has_element?(view, "#sales-attention-items-table", "Attention 13")
    refute has_element?(view, "#sales-attention-items-table", "Attention 01")
  end

  @tag :skip
  test "renders the outcome attention empty state", %{conn: conn} do
    user = insert_user!("sales-empty@example.com")

    conn = init_test_session(conn, %{"user_id" => user.id})

    {:ok, view, _html} = live(conn, ~p"/sales")

    assert has_element?(view, "#sales-attention-items-table", "Nothing needs attention right now")
    assert has_element?(view, "#sales-widget-on-track [data-part='value']", "0")
    assert has_element?(view, "#sales-widget-at-risk [data-part='value']", "0")
    assert has_element?(view, "#sales-widget-off-track [data-part='value']", "0")
  end

  test "renders the revenue snapshot widgets", %{conn: conn} do
    user = insert_user!("sales-revenue@example.com")

    insert_account!(%{
      account_key: "enterprise:northstar",
      name: "Northstar",
      segment: :customer,
      status: "active",
      currency: "EUR",
      current_value: 7_980,
      next_renewal_date: ~D[2027-01-01]
    })

    conn = init_test_session(conn, %{"user_id" => user.id})

    {:ok, view, _html} = live(conn, ~p"/sales")

    assert has_element?(view, "#sales-widget-mrr", "MRR Equivalent")
    assert has_element?(view, "#sales-widget-mrr [data-part='value']", "EUR 665.00")
    assert has_element?(view, "#sales-widget-arr", "Estimated ARR")
    assert has_element?(view, "#sales-widget-arr [data-part='value']", "EUR 7,980.00")
    assert has_element?(view, "#sales-widget-mrr-tooltip")
    assert has_element?(view, "#sales-widget-arr-tooltip")
    assert has_element?(view, "#sales-widget-mrr-tooltip", "monthly recurring revenue in EUR")
    assert has_element?(view, "#sales-widget-arr-tooltip", "Annualizes the MRR equivalent")
  end

  test "renders upcoming customer renewals ordered by renewal date", %{conn: conn} do
    user = insert_user!("sales-renewals@example.com")

    first_renewal = Date.utc_today() |> Date.add(30)
    second_renewal = Date.utc_today() |> Date.add(60)
    past_renewal = Date.utc_today() |> Date.add(-1)

    first_account =
      insert_account!(%{
        account_key: "customer:first-renewal",
        name: "First Renewal",
        primary_domain: "first.example",
        segment: :customer,
        status: "active",
        currency: "EUR",
        current_value: Decimal.new("0.00"),
        next_renewal_date: first_renewal
      })

    %Term{account_id: first_account.id}
    |> Term.changeset(%{
      source: "atlas",
      payment: "yearly",
      start_date: Date.add(Date.utc_today(), -335),
      end_date: first_renewal,
      total: Decimal.new("12000.00"),
      currency: "EUR"
    })
    |> Repo.insert!()

    second_account =
      insert_account!(%{
        account_key: "customer:second-renewal",
        name: "Second Renewal",
        segment: :customer,
        status: "active",
        currency: "USD",
        current_value: Decimal.new("24000.00"),
        next_renewal_date: second_renewal
      })

    _past_account =
      insert_account!(%{
        account_key: "customer:past-renewal",
        name: "Past Renewal",
        segment: :customer,
        status: "active",
        next_renewal_date: past_renewal
      })

    _prospect =
      insert_account!(%{
        account_key: "prospect:renewal",
        name: "Prospect Renewal",
        segment: :prospect,
        next_renewal_date: first_renewal
      })

    _churned_customer =
      insert_account!(%{
        account_key: "customer:churned-renewal",
        name: "Churned Renewal",
        segment: :customer,
        status: "churned",
        next_renewal_date: first_renewal
      })

    conn = init_test_session(conn, %{"user_id" => user.id})

    {:ok, view, _html} = live(conn, ~p"/sales")

    assert has_element?(view, "#sales-renewals-table tr[id='#{first_account.id}']", "First Renewal")
    assert has_element?(view, "#sales-renewals-table tr[id='#{first_account.id}']", format_date(first_renewal))
    assert has_element?(view, "#sales-renewals-table tr[id='#{first_account.id}']", "Renews in 30 days")
    assert has_element?(view, "#sales-renewals-table tr[id='#{first_account.id}']", "EUR 12,000.00")

    assert has_element?(view, "#sales-renewals-table tr[id='#{second_account.id}']", "Second Renewal")
    assert has_element?(view, "#sales-renewals-table tr[id='#{second_account.id}']", format_date(second_renewal))
    refute has_element?(view, "#sales-renewals-table", "Past Renewal")
    refute has_element?(view, "#sales-renewals-table", "Prospect Renewal")
    refute has_element?(view, "#sales-renewals-table", "Churned Renewal")
  end

  test "renders open and scheduled Stripe invoices in a single table, hiding 0-amount invoices", %{conn: conn} do
    user = insert_user!("sales-invoices@example.com")

    account =
      insert_account!(%{
        account_key: "demo:billing",
        name: "Billing Co",
        primary_domain: "billing.test",
        segment: :customer,
        stripe_customer_id: "cus_billing"
      })

    fixture_key =
      put_stripe_page_fixture(fn _opts ->
        {:ok,
         %{
           invoices: [
             %StripeInvoice{
               id: "in_open",
               number: "INV-OPEN",
               due_date: ~D[2026-06-01],
               amount_value: Decimal.new("1200.00"),
               amount_currency: "EUR",
               status: "open",
               hosted_url: "https://stripe.example/invoices/in_open",
               customer_id: "cus_billing"
             },
             %StripeInvoice{
               id: "in_open_zero",
               number: "INV-OPEN-ZERO",
               due_date: ~D[2026-06-15],
               amount_value: Decimal.new("0.00"),
               amount_currency: "EUR",
               status: "open",
               hosted_url: "https://stripe.example/invoices/in_open_zero",
               customer_id: "cus_billing"
             },
             %StripeInvoice{
               id: "in_draft",
               number: nil,
               due_date: nil,
               amount_value: Decimal.new("4500.00"),
               amount_currency: "USD",
               status: "draft",
               hosted_url: nil,
               customer_id: "cus_unknown"
             },
             %StripeInvoice{
               id: "in_draft_zero",
               number: "INV-DRAFT-ZERO",
               due_date: ~D[2026-07-01],
               amount_value: Decimal.new("0.00"),
               amount_currency: "USD",
               status: "draft",
               hosted_url: nil,
               customer_id: "cus_unknown"
             },
             %StripeInvoice{
               id: "in_paid",
               number: "INV-PAID",
               due_date: ~D[2026-04-01],
               amount_value: Decimal.new("9999.00"),
               amount_currency: "EUR",
               status: "paid",
               hosted_url: "https://stripe.example/invoices/in_paid",
               customer_id: "cus_billing"
             }
           ],
           has_more: false
         }}
      end)

    conn = init_test_session(conn, %{"user_id" => user.id})

    {:ok, view, _html} = live(conn, ~p"/sales?_stripe_fixture=#{fixture_key}")

    assert has_element?(view, "#sales-invoices-table", "INV-OPEN")
    assert has_element?(view, "#sales-invoices-table", "Billing Co")
    assert has_element?(view, "#sales-invoices-table", "Open in Stripe")
    assert has_element?(view, "#sales-invoices-table", "Scheduled")
    assert has_element?(view, "#sales-invoices-table", "Unlinked customer")
    refute has_element?(view, "#sales-invoices-table", "INV-OPEN-ZERO")
    refute has_element?(view, "#sales-invoices-table", "INV-DRAFT-ZERO")
    refute has_element?(view, "#sales-invoices-table", "INV-PAID")

    _ = account
  end

  test "renders the pagination control when Stripe reports more invoices", %{conn: conn} do
    user = insert_user!("sales-invoices-paginated@example.com")

    fixture_key =
      put_stripe_page_fixture(fn opts ->
        assert Keyword.get(opts, :after) == nil
        assert Keyword.get(opts, :before) == nil
        assert Keyword.get(opts, :status) == "open"

        {:ok,
         %{
           invoices: [
             %StripeInvoice{
               id: "in_first",
               number: "INV-FIRST",
               due_date: ~D[2026-06-01],
               amount_value: Decimal.new("100.00"),
               amount_currency: "EUR",
               status: "open",
               hosted_url: "https://stripe.example/invoices/in_first",
               customer_id: "cus_a"
             },
             %StripeInvoice{
               id: "in_last",
               number: "INV-LAST",
               due_date: ~D[2026-06-02],
               amount_value: Decimal.new("200.00"),
               amount_currency: "EUR",
               status: "open",
               hosted_url: "https://stripe.example/invoices/in_last",
               customer_id: "cus_b"
             }
           ],
           has_more: true
         }}
      end)

    conn = init_test_session(conn, %{"user_id" => user.id})

    {:ok, view, _html} = live(conn, ~p"/sales?_stripe_fixture=#{fixture_key}")

    assert has_element?(view, "[data-part='pagination']")
    assert has_element?(view, "[data-part='pagination'] a[href*=\"invoices-after=in_last\"]", "Next")
    refute has_element?(view, "[data-part='pagination'] a", "Prev")
  end

  test "passes cursor params from the URL into the Stripe call", %{conn: conn} do
    user = insert_user!("sales-invoices-cursor@example.com")

    test_pid = self()

    fixture_key =
      put_stripe_page_fixture(fn opts ->
        send(test_pid, {:list_invoices_page_opts, opts})

        {:ok,
         %{
           invoices: [
             %StripeInvoice{
               id: "in_after",
               number: "INV-AFTER",
               due_date: ~D[2026-06-10],
               amount_value: Decimal.new("500.00"),
               amount_currency: "EUR",
               status: "open",
               hosted_url: "https://stripe.example/invoices/in_after",
               customer_id: "cus_c"
             }
           ],
           has_more: false
         }}
      end)

    conn = init_test_session(conn, %{"user_id" => user.id})

    {:ok, view, _html} = live(conn, ~p"/sales?invoices-after=in_prev&_stripe_fixture=#{fixture_key}")

    assert_receive {:list_invoices_page_opts, opts}
    assert Keyword.get(opts, :after) == "in_prev"
    assert Keyword.get(opts, :before) == nil
    assert Keyword.get(opts, :status) == "open"

    assert has_element?(view, "[data-part='pagination'] a[href*=\"invoices-before=in_after\"]", "Prev")
  end

  test "renders the invoices empty state when Stripe is disabled", %{conn: conn} do
    user = insert_user!("sales-invoices-empty@example.com")

    conn = init_test_session(conn, %{"user_id" => user.id})

    {:ok, view, _html} = live(conn, ~p"/sales")

    assert has_element?(view, "#sales-invoices-table", "No open or scheduled invoices")
  end

  defp insert_user!(email) do
    %User{}
    |> User.changeset(%{email: email, name: "Atlas User"})
    |> Repo.insert!()
  end

  defp put_stripe_page_fixture(response) do
    fixture_key = "page-#{System.unique_integer([:positive])}"

    StripeClient.put_list_invoices_page(fixture_key, response)
    fixture_key
  end

  defp format_date(%Date{} = date), do: Calendar.strftime(date, "%b %d, %Y")

  defp insert_account!(attrs) do
    defaults = %{
      account_key: "account:#{System.unique_integer([:positive])}",
      name: "Account",
      segment: :lead
    }

    %Account{}
    |> Account.changeset(Map.merge(defaults, attrs))
    |> Repo.insert!()
  end

  defp insert_outcome!(account, attrs) do
    defaults = %{
      title: "Customer outcome",
      status: "active",
      health: "on_track",
      motion: "adoption",
      success_measure: "Weekly active developers",
      baseline: "10",
      target: "30",
      target_date: ~D[2026-08-31]
    }

    %Outcome{account_id: account.id}
    |> Outcome.changeset(Map.merge(defaults, attrs))
    |> Repo.insert!()
  end

  defp insert_review!(outcome, attrs) do
    defaults = %{
      health: outcome.health,
      summary: "The latest evidence supports the projected health.",
      evidence: %{"items" => ["Usage evidence"]},
      reviewed_at: ~U[2026-07-14 10:00:00Z]
    }

    %OutcomeReview{outcome_id: outcome.id}
    |> OutcomeReview.changeset(Map.merge(defaults, attrs))
    |> Repo.insert!()
  end
end

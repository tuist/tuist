defmodule AtlasWeb.NativeControllerTest do
  use AtlasWeb.ConnCase, async: true
  use Mimic

  import Atlas.FinanceFixtures
  import Ecto.Query

  alias Atlas.Accounts
  alias Atlas.Accounts.Account
  alias Atlas.Accounts.Event
  alias Atlas.Accounts.ExchangeRates
  alias Atlas.Accounts.Term
  alias Atlas.Audit.Activity
  alias Atlas.Documents.Document
  alias Atlas.Finance.Invoice
  alias Atlas.OAuth.AccessTokens
  alias Atlas.Repo
  alias Atlas.Tasks
  alias Atlas.Tasks.Task

  setup do
    {api, user} = api_user(["accounts:write", "finance:write"])
    %{api: api, user: user}
  end

  test "every native endpoint requires a bearer token, even with a browser session", %{conn: conn} do
    {session, _user} = log_in_user(conn)

    for api <- [conn, session, put_req_header(build_conn(), "authorization", "Bearer invalid")],
        {method, path} <- [{:get, "/api/native/profile"}] ++ endpoints() do
      response = dispatch(api, @endpoint, method, path, %{})
      assert json_response(response, 401)["error"] == "invalid_token"
      assert get_resp_header(response, "cache-control") == ["no-store"]
    end
  end

  test "profile exposes only caller name/email and the running application's version", %{api: api, user: user} do
    response = get(api, "/api/native/profile?user_id=someone-else")

    assert json_response(response, 200) == %{
             "server_version" => to_string(Application.spec(:atlas, :vsn)),
             "user" => %{"name" => user.name, "email" => user.email},
             "push_notifications" => %{"ios" => false, "android" => false}
           }

    assert get_resp_header(response, "cache-control") == ["no-store"]
  end

  test "any teammate can create, read, edit and complete shared tasks with string fields", %{user: user} do
    {api, teammate} = api_user([], "Task teammate")
    {:ok, account} = Accounts.create_manual_account(%{name: "Linked account"})

    created =
      api
      |> post("/api/native/tasks", %{
        title: "Review proposal",
        assignee_id: "",
        account_id: account.id,
        due_on: "2027-02-03",
        remind_at: "2027-02-02T14:30:00+02:00",
        status: "completed"
      })
      |> json_response(201)

    assert %{"item" => %{"id" => id, "can_edit" => true, "can_delete" => true, "fields" => fields}} = created
    assert fields["status"] == "open"
    assert fields["assignee_id"] == teammate.id
    assert fields["assignee_name"] == teammate.name
    assert fields["account_name"] == account.name
    assert fields["remind_at"] == "2027-02-02T12:30:00Z"
    assert fields["description"] == ""
    assert Enum.all?(fields, fn {_key, value} -> is_binary(value) end)
    assert api |> get("/api/native/tasks/#{id}") |> json_response(200) == created

    assert %{
             "item" => %{
               "fields" => %{"assignee_id" => assignee, "assignee_name" => "Other owner", "description" => "Updated"}
             }
           } =
             api
             |> patch("/api/native/tasks/#{id}", %{assignee_id: user.id, description: "Updated"})
             |> json_response(200)

    assert assignee == user.id

    page = api |> get("/api/native/tasks") |> json_response(200)
    assert page["can_write"]
    assert %{"id" => teammate.id, "name" => teammate.name} in page["options"]["users"]
    assert %{"id" => account.id, "name" => account.name} in page["options"]["accounts"]
    assert page["summary"] == []

    assert %{"item" => %{"fields" => %{"status" => "completed"}}} =
             api |> post("/api/native/tasks/#{id}/complete") |> json_response(200)

    assert api |> post("/api/native/tasks/#{id}/complete") |> json_response(409) == %{"error" => "resource_conflict"}
    assert api |> delete("/api/native/tasks/#{id}") |> json_response(200) == %{"deleted" => true}
    assert api |> get("/api/native/tasks/#{id}") |> json_response(404)
    assert_audit("task.deleted", id, teammate.id)
  end

  test "account CRUD uses schema choices and preserves decimal/date strings", %{api: api, user: user} do
    attrs = %{
      name: "Native account",
      description: "Sales notes",
      segment: "lead",
      status: "active",
      primary_domain: "native.example",
      deal_stage: hd(Account.deal_stages()),
      currency: "eur",
      current_value: "1234.56",
      next_renewal_date: "2027-03-04",
      legal_name: "Native GmbH",
      url: "https://native.example",
      hosting: "self_hosted",
      plan_tier: "enterprise"
    }

    assert %{"item" => %{"id" => id, "fields" => fields}} =
             api |> post("/api/native/accounts", attrs) |> json_response(201)

    assert fields["current_value"] == "1234.56"
    assert fields["currency"] == "EUR"
    assert fields["next_renewal_date"] == "2027-03-04"
    assert fields["hosting"] == "self_hosted"
    assert fields["plan_tier"] == "enterprise"
    assert_audit("account.created", id, user.id)

    assert %{"item" => %{"fields" => %{"description" => "", "name" => "Renamed"}}} =
             api |> patch("/api/native/accounts/#{id}", %{name: "Renamed", description: ""}) |> json_response(200)

    assert api |> get("/api/native/accounts/#{id}") |> json_response(200)
    page = api |> get("/api/native/accounts") |> json_response(200)
    assert page["options"]["segments"] == Enum.map(Account.segments(), &to_string/1)
    assert page["options"]["statuses"] == Account.statuses()
    assert page["options"]["deal_stages"] == Account.deal_stages()
    assert api |> delete("/api/native/accounts/#{id}") |> json_response(200) == %{"deleted" => true}
    assert_audit("account.deleted", id, user.id)
  end

  test "read-only and unscoped users cannot bypass account or finance write permissions", %{api: writer} do
    for {resource, attrs} <- [{"accounts", %{name: "Scoped account"}}, {"invoices", invoice_attrs()}] do
      %{"item" => %{"id" => id}} = writer |> post("/api/native/#{resource}", attrs) |> json_response(201)
      area = if resource == "accounts", do: "accounts", else: "finance"
      {reader, _user} = api_user(["#{area}:read"])
      {unscoped, _user} = api_user([])

      assert %{"items" => [%{"can_edit" => false, "can_delete" => false}], "can_write" => false} =
               reader |> get("/api/native/#{resource}") |> json_response(200)

      assert reader |> get("/api/native/#{resource}/#{id}") |> json_response(200)

      for {method, path} <- [
            {:post, "/api/native/#{resource}"},
            {:patch, "/api/native/#{resource}/#{id}"},
            {:delete, "/api/native/#{resource}/#{id}"}
          ] do
        response = dispatch(reader, @endpoint, method, path, attrs)
        assert json_response(response, 403) == %{"error" => "forbidden"}
        assert get_resp_header(response, "cache-control") == ["no-store"]
      end

      assert unscoped |> get("/api/native/#{resource}") |> json_response(403)
      assert unscoped |> get("/api/native/#{resource}/#{id}") |> json_response(403)
    end
  end

  test "account details include related data and derived contract value without exposing storage or restricted contents" do
    {reader, _user} = api_user(["accounts:read"])
    {document_reader, _user} = api_user(["accounts:read", "documents:read"])
    {:ok, account} = Accounts.create_manual_account(%{name: "Detailed account", current_value: "5", currency: "EUR"})
    {:ok, other} = Accounts.create_manual_account(%{name: "Unrelated account"})

    {:ok, contact} =
      Accounts.create_contact(account, %{full_name: "Taylor", email: "taylor@example.org", is_primary: true})

    {:ok, _contact} = Accounts.create_contact(other, %{full_name: "Not related", email: "other@example.org"})

    term =
      Repo.insert!(%Term{
        account_id: account.id,
        source: "atlas",
        payment: "yearly",
        start_date: ~D[2020-01-01],
        total: Decimal.new("1234.56"),
        currency: "USD"
      })

    Repo.insert!(%Event{
      account_id: account.id,
      author_id: nil,
      external_id: Ecto.UUID.generate(),
      source: "atlas",
      kind: "note",
      title: "Follow up",
      body: "Sales context",
      occurred_at: ~U[2026-10-20 12:00:00Z]
    })

    document =
      Repo.insert!(%Document{
        account_id: account.id,
        title: "Contract",
        original_filename: "contract.pdf",
        source: "upload",
        content_type: "application/pdf",
        storage_bucket: "private",
        storage_key: Ecto.UUID.generate(),
        status: "ready",
        summary: "Restricted document contents"
      })

    response = reader |> get("/api/native/accounts/#{account.id}") |> json_response(200)

    assert %{"item" => %{"can_edit" => false, "can_delete" => false, "fields" => fields, "details" => details}} =
             response

    assert Decimal.equal?(Decimal.new(fields["current_value"]), Decimal.new("5"))
    assert fields["contract_value"] == "1234.56"
    assert fields["contract_currency"] == "USD"
    assert [%{"id" => contact_id, "fields" => %{"full_name" => "Taylor", "is_primary" => "true"}}] = details["contacts"]
    assert contact_id == contact.id
    assert [%{"id" => term_id, "fields" => %{"total" => "1234.56", "start_date" => "2020-01-01"}}] = details["terms"]
    assert term_id == term.id
    assert [%{"fields" => %{"body" => "Sales context", "author_name" => ""}}] = details["events"]
    assert [%{"id" => document_id, "fields" => %{"title" => "Contract"} = document_fields}] = details["documents"]
    assert document_id == document.id
    refute Map.has_key?(document_fields, "summary")
    refute Jason.encode!(response) =~ "storage_key"
    refute Jason.encode!(response) =~ "Restricted document contents"
    refute Jason.encode!(response) =~ "Not related"

    full = document_reader |> get("/api/native/accounts/#{account.id}") |> json_response(200)
    assert hd(full["item"]["details"]["documents"])["fields"]["summary"] == "Restricted document contents"
    assert reader |> get("/api/native/invoices") |> json_response(403) == %{"error" => "forbidden"}
    assert document_reader |> get("/api/native/invoices") |> json_response(403) == %{"error" => "forbidden"}
  end

  test "revoked OAuth grants immediately deny account details and finance overview", %{api: api} do
    {:ok, account} = Accounts.create_manual_account(%{name: "Private account"})
    paths = ["/api/native/accounts/#{account.id}", "/api/native/invoices"]
    for path <- paths, do: assert(api |> get(path) |> json_response(200))
    ["Bearer " <> value] = get_req_header(api, "authorization")
    assert {:ok, _revoked} = value |> then(&AccessTokens.get_by(value: &1)) |> AccessTokens.revoke()

    for path <- paths do
      response = get(api, path)
      assert json_response(response, 401)["error"] == "invalid_token"
      assert get_resp_header(response, "cache-control") == ["no-store"]
    end
  end

  test "finance overview unifies bank currencies, excludes transfers, and ignores invoice filters" do
    stub(DateTime, :utc_now, fn -> ~U[2026-10-22 12:00:00.000000Z] end)
    {api, _user} = api_user(["finance:read"])

    stub(ExchangeRates, :latest_rates, fn _ ->
      {:ok, %{published_on: ~D[2026-10-21], rates: %{"USD" => Decimal.new("2"), "GBP" => Decimal.new("0.5")}}}
    end)

    source = insert_finance_source!()
    eur = insert_finance_account!(source, %{available_balance_value: Decimal.new("900")})

    usd =
      insert_finance_account!(source, %{
        currency: "USD",
        available_balance_currency: "USD",
        available_balance_value: Decimal.new("200")
      })

    gbp =
      insert_finance_account!(source, %{
        currency: "GBP",
        available_balance_currency: "GBP",
        available_balance_value: Decimal.new("50")
      })

    for {account, amount, direction, occurred_at, runway?} <- [
          {eur, "1", "debit", ~U[2026-01-01 12:00:00Z], true},
          {usd, "240", "debit", ~U[2026-09-30 23:59:59Z], true},
          {eur, "10", "credit", ~U[2026-10-01 00:00:00Z], true},
          {usd, "80", "credit", ~U[2026-10-20 12:00:00Z], true},
          {gbp, "75", "debit", ~U[2026-10-20 12:00:00Z], true},
          {usd, "40", "debit", ~U[2026-10-20 12:00:00Z], true},
          {eur, "9999", "credit", ~U[2026-10-20 12:00:00Z], false}
        ] do
      insert_finance_transaction!(account, %{
        amount_value: Decimal.new(amount),
        direction: direction,
        settled_at: occurred_at,
        booked_at: occurred_at,
        affects_runway: runway?
      })
    end

    insert_finance_invoice!(%{total_amount_value: Decimal.new("99999"), invoice_date: ~D[2026-10-20]})
    response = get(api, "/api/native/invoices?query=no-match&status=failed")
    assert get_resp_header(response, "cache-control") == ["no-store"]
    assert %{"items" => [], "can_write" => false, "finance_overview" => overview} = json_response(response, 200)
    assert overview["currency"] == "EUR"
    assert overview["as_of"] == "2026-10-22"
    assert overview["fx_published_on"] == "2026-10-21"
    assert overview["account_count"] == 3
    assert overview["excluded_currencies"] == []
    assert Decimal.equal?(Decimal.new(overview["available_cash"]), Decimal.new("1100"))
    assert Decimal.equal?(Decimal.new(overview["monthly_burn"]), Decimal.new("40"))
    assert Decimal.equal?(Decimal.new(overview["runway_months"]), Decimal.new("27.5"))

    assert Enum.take(overview["months"], -2) == [
             %{"month" => "2026-09", "income" => "0", "expense" => "120.00"},
             %{"month" => "2026-10", "income" => "50.00", "expense" => "170.00"}
           ]

    assert api |> get("/api/native/accounts/#{Ecto.UUID.generate()}") |> json_response(403)
  end

  test "finance does not present missing accounts or incomplete currency conversion as valid totals", %{api: api} do
    empty = api |> get("/api/native/invoices") |> json_response(200) |> Map.fetch!("finance_overview")
    assert empty["account_count"] == 0
    assert empty["available_cash"] == nil
    assert empty["months"] == []
    stub(ExchangeRates, :latest_rates, fn _ -> {:error, :unavailable} end)
    insert_finance_account!(insert_finance_source!(), %{currency: "USD", available_balance_currency: "USD"})
    missing = api |> get("/api/native/invoices") |> json_response(200) |> Map.fetch!("finance_overview")
    assert missing["excluded_currencies"] == ["USD"]

    assert Map.take(missing, ~w(available_cash monthly_burn runway_months months)) == %{
             "available_cash" => nil,
             "monthly_burn" => nil,
             "runway_months" => nil,
             "months" => []
           }
  end

  test "manual invoice CRUD owns provenance, while document-less imported invoices remain read-only", %{
    api: api,
    user: user
  } do
    attrs =
      Map.merge(invoice_attrs(), %{
        metadata: %{source: "imported"},
        document_id: Ecto.UUID.generate(),
        finance_transaction_id: Ecto.UUID.generate()
      })

    assert %{"item" => %{"id" => id, "can_edit" => true, "can_delete" => true, "fields" => fields}} =
             api |> post("/api/native/invoices", attrs) |> json_response(201)

    assert fields["due_date"] == ""
    assert fields["status"] == "needs_review"
    invoice = Repo.get!(Invoice, id)
    assert invoice.metadata == %{"source" => "manual", "created_by_id" => user.id}
    assert invoice.document_id == nil
    assert invoice.finance_transaction_id == nil
    assert_audit("finance_invoice.created", id, user.id)

    assert %{"item" => %{"fields" => %{"total_amount_value" => "27.35", "status" => "extracted"}}} =
             api
             |> patch("/api/native/invoices/#{id}", %{total_amount_value: "27.35", status: "extracted"})
             |> json_response(200)

    assert api |> get("/api/native/invoices/#{id}") |> json_response(200)

    imported = insert_finance_invoice!(%{document_id: nil, metadata: %{}})

    assert %{"item" => %{"can_edit" => false, "can_delete" => false}} =
             api |> get("/api/native/invoices/#{imported.id}") |> json_response(200)

    assert api
           |> patch("/api/native/invoices/#{imported.id}", %{vendor_name: "Forged", metadata: %{source: "manual"}})
           |> json_response(403) == %{"error" => "read_only"}

    assert api |> delete("/api/native/invoices/#{imported.id}") |> json_response(403)
    assert Repo.get!(Invoice, imported.id).vendor_name == imported.vendor_name

    assert api |> delete("/api/native/invoices/#{id}") |> json_response(200) == %{"deleted" => true}
    assert Repo.get(Invoice, id) == nil
    assert_audit("finance_invoice.deleted", id, user.id)
  end

  test "Flop pages every dataset at 25 with literal search and stable disjoint pages", %{api: api, user: user} do
    for resource <- ["tasks", "accounts", "invoices"] do
      for index <- 1..26 do
        case resource do
          "tasks" -> Tasks.create_task(%{title: "Match #{index}", assignee_id: user.id}, user)
          "accounts" -> Accounts.create_manual_account(%{name: "Match #{index}"})
          "invoices" -> insert_finance_invoice!(%{vendor_name: "Match #{index}"})
        end
      end

      first = api |> get("/api/native/#{resource}?query=Match") |> json_response(200)
      second = api |> get("/api/native/#{resource}?query=Match&page=2") |> json_response(200)
      assert %{"page" => 1, "total_pages" => 2, "total_count" => 26} = first
      assert %{"page" => 2, "total_pages" => 2, "total_count" => 26} = second
      assert length(first["items"]) == 25
      assert length(second["items"]) == 1
      ids = Enum.map(first["items"] ++ second["items"], & &1["id"])
      assert length(Enum.uniq(ids)) == 26

      assert %{"items" => [], "total_count" => 0} =
               api |> get("/api/native/#{resource}?query=%25") |> json_response(200)
    end
  end

  test "reminder grouping is global across pages and includes the exact UTC boundary", %{api: api, user: user} do
    now = DateTime.utc_now() |> DateTime.truncate(:second)
    past = DateTime.add(now, -1, :second)
    future = DateTime.add(now, 1, :second)

    overdue =
      for index <- 1..26 do
        task!(user, %{
          title: "Overdue #{index}",
          remind_at: if(index <= 24, do: past, else: now),
          reminded_at: now
        })
      end

    upcoming = task!(user, %{remind_at: future, due_on: Date.add(Date.utc_today(), -1)})
    none = task!(user, %{due_on: Date.add(Date.utc_today(), -1)})
    completed = task!(user, %{status: "completed", remind_at: past})
    stub(DateTime, :utc_now, fn -> now end)

    expected_overdue = Enum.sort_by(overdue, &{DateTime.to_unix(&1.remind_at), &1.id}) |> Enum.map(& &1.id)
    first = api |> get("/api/native/tasks?group_by=reminder") |> json_response(200)
    second = api |> get("/api/native/tasks?group_by=reminder&page=2") |> json_response(200)
    assert %{"total_count" => 29, "total_pages" => 2} = first
    assert length(first["items"]) == 25
    assert Enum.map(first["items"], & &1["fields"]["reminder_group"]) == List.duplicate("overdue", 25)
    assert Enum.map(second["items"], & &1["fields"]["reminder_group"]) == ~w(overdue upcoming none completed)

    assert Enum.map(first["items"] ++ second["items"], & &1["id"]) ==
             expected_overdue ++ [upcoming.id, none.id, completed.id]

    for {filter, expected_ids} <- [
          {"overdue", expected_overdue},
          {"upcoming", [upcoming.id]},
          {"none", [none.id]}
        ] do
      pages =
        for page <- 1..ceil(length(expected_ids) / 25),
            do: api |> get("/api/native/tasks?reminder=#{filter}&group_by=reminder&page=#{page}") |> json_response(200)

      assert hd(pages)["total_count"] == length(expected_ids)
      assert Enum.flat_map(pages, &Enum.map(&1["items"], fn item -> item["id"] end)) == expected_ids
    end

    assert %{"items" => [], "total_count" => 0} =
             api |> get("/api/native/tasks?status=completed&reminder=overdue") |> json_response(200)

    assert api
           |> get("/api/native/tasks/#{completed.id}")
           |> json_response(200)
           |> get_in(["item", "fields", "reminder_group"]) ==
             "completed"

    default = api |> get("/api/native/tasks") |> json_response(200)
    all = api |> get("/api/native/tasks?status=&assignee_id=&reminder=&group_by=") |> json_response(200)
    assert default == all

    expected_default =
      (overdue ++ [upcoming, none, completed])
      |> Enum.sort_by(&{DateTime.to_unix(&1.inserted_at), &1.id}, :desc)
      |> Enum.take(25)
      |> Enum.map(& &1.id)

    assert Enum.map(default["items"], & &1["id"]) == expected_default
  end

  test "combined task filters apply before the Flop count and both pages", %{api: api, user: user} do
    {_api, other} = api_user([])
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    expected = for _index <- 1..26, do: task!(user, %{title: "Needle", remind_at: now})
    task!(other, %{title: "Needle", remind_at: now})
    task!(user, %{title: "Needle", status: "completed", remind_at: now})
    task!(user, %{title: "Needle", remind_at: DateTime.add(now, 1, :second)})
    task!(user, %{title: "Needle"})
    task!(user, %{title: "Different", remind_at: now})
    stub(DateTime, :utc_now, fn -> now end)

    params = "query=Needle&status=open&assignee_id=#{user.id}&reminder=overdue&group_by=reminder"
    first = api |> get("/api/native/tasks?#{params}") |> json_response(200)
    second = api |> get("/api/native/tasks?#{params}&page=2") |> json_response(200)
    assert %{"total_count" => 26, "total_pages" => 2} = first
    assert length(first["items"]) == 25
    assert length(second["items"]) == 1
    assert Enum.map(first["items"] ++ second["items"], & &1["id"]) == Enum.sort(Enum.map(expected, & &1.id))
  end

  test "account enum filters combine with search before pagination", %{api: api} do
    expected =
      for index <- 1..26 do
        {:ok, account} =
          Accounts.create_manual_account(%{
            name: "Needle #{index}",
            segment: "prospect",
            status: "trial",
            deal_stage: "security_review"
          })

        account.id
      end

    for attrs <- [
          %{name: "Needle", segment: "lead", status: "trial", deal_stage: "security_review"},
          %{name: "Needle", segment: "prospect", status: "active", deal_stage: "security_review"},
          %{name: "Needle", segment: "prospect", status: "trial", deal_stage: "poc"},
          %{name: "Different", segment: "prospect", status: "trial", deal_stage: "security_review"}
        ],
        do: Accounts.create_manual_account(attrs)

    params = "query=Needle&segment=prospect&status=trial&deal_stage=security_review"
    first = api |> get("/api/native/accounts?#{params}") |> json_response(200)
    second = api |> get("/api/native/accounts?#{params}&page=2") |> json_response(200)
    assert %{"total_count" => 26, "total_pages" => 2} = first
    assert length(first["items"]) == 25
    assert length(second["items"]) == 1
    assert Enum.sort(Enum.map(first["items"] ++ second["items"], & &1["id"])) == Enum.sort(expected)

    assert api |> get("/api/native/accounts") |> json_response(200) ==
             api |> get("/api/native/accounts?segment=&status=&deal_stage=") |> json_response(200)
  end

  test "list filters reject unknown keys, wrong resources, malformed values and shapes", %{api: api} do
    for {resource, params} <-
          [
            {"tasks", "status=active"},
            {"tasks", "assignee_id=invalid"},
            {"tasks", "reminder=completed"},
            {"tasks", "group_by=due_on"},
            {"tasks", "segment="},
            {"accounts", "status=open"},
            {"accounts", "segment=other"},
            {"accounts", "deal_stage=other"},
            {"accounts", "assignee_id="},
            {"accounts", "group_by=reminder"},
            {"invoices", "status=paid"},
            {"invoices", "reminder="}
          ] ++
            for(
              resource <- ~w(tasks accounts invoices),
              query <- ["unknown=", "page_size=50", "filters[status]=open", "status[]=open", "resource=tasks"],
              do: {resource, query}
            ) do
      response = get(api, "/api/native/#{resource}?#{params}")
      assert json_response(response, 422) == %{"error" => "invalid_params"}
      assert get_resp_header(response, "cache-control") == ["no-store"]
    end
  end

  test "invoice summary covers the full dataset by invoice month and currency, independent of search/page", %{api: api} do
    source = insert_finance_source!()
    account = insert_finance_account!(source)
    transaction = insert_finance_transaction!(account, %{settled_at: ~U[2027-04-01 00:00:00Z]})

    for index <- 1..26 do
      insert_finance_invoice!(%{
        vendor_name: "Paged #{index}",
        status: "needs_review",
        invoice_date: ~D[2027-01-31],
        total_amount_value: Decimal.new("1.25"),
        total_amount_currency: "EUR"
      })
    end

    insert_finance_invoice!(%{
      vendor_name: "Outside search",
      invoice_date: ~D[2027-01-01],
      total_amount_value: Decimal.new("7.35"),
      total_amount_currency: "EUR",
      finance_transaction_id: transaction.id
    })

    insert_finance_invoice!(%{
      invoice_date: ~D[2027-01-15],
      total_amount_value: Decimal.new("10.50"),
      total_amount_currency: "USD"
    })

    insert_finance_invoice!(%{
      invoice_date: ~D[2027-02-01],
      total_amount_value: Decimal.new("4.20"),
      total_amount_currency: "EUR"
    })

    assert %{"items" => [_item], "summary" => summary} =
             api |> get("/api/native/invoices?query=Paged&status=needs_review&page=2") |> json_response(200)

    assert summary == [
             %{"month" => "2027-01", "currency" => "EUR", "amount" => "39.85"},
             %{"month" => "2027-01", "currency" => "USD", "amount" => "10.50"},
             %{"month" => "2027-02", "currency" => "EUR", "amount" => "4.20"}
           ]

    assert api
           |> get("/api/native/invoices?status=needs_review")
           |> json_response(200)
           |> Map.take(["total_count", "total_pages"]) ==
             %{"total_count" => 26, "total_pages" => 2}

    assert api |> get("/api/native/invoices") |> json_response(200) ==
             api |> get("/api/native/invoices?status=") |> json_response(200)
  end

  test "invalid IDs, dates, shapes and pages return sanitized no-store errors", %{api: api} do
    for resource <- ["tasks", "accounts", "invoices"] do
      for id <- ["invalid", Ecto.UUID.generate()], method <- [:get, :patch, :delete] do
        response = dispatch(api, @endpoint, method, "/api/native/#{resource}/#{id}", %{})
        assert json_response(response, 404) == %{"error" => "not_found"}
        assert get_resp_header(response, "cache-control") == ["no-store"]
      end

      for query <- ["page=0", "page=abc", "page[]=1", "query[]=bad"] do
        assert api |> get("/api/native/#{resource}?#{query}") |> json_response(422) == %{"error" => "invalid_params"}
      end
    end

    for {resource, attrs} <- [
          {"tasks", %{title: %{invalid: true}}},
          {"tasks", %{title: "Bad date", due_on: "not-a-date"}},
          {"tasks", %{title: "Bad UUID", assignee_id: "invalid"}},
          {"accounts", %{name: "Bad segment", segment: "not-a-segment"}},
          {"invoices", Map.put(invoice_attrs(), :total_amount_value, "not-a-number")},
          {"invoices", Map.put(invoice_attrs(), :invoice_date, "not-a-date")}
        ] do
      response = post(api, "/api/native/#{resource}", attrs)
      assert %{"error" => _error} = json_response(response, 422)
      assert get_resp_header(response, "cache-control") == ["no-store"]
    end
  end

  defp task!(user, attrs) do
    %Task{title: "Task", assignee_id: user.id, created_by_id: user.id}
    |> struct!(attrs)
    |> Repo.insert!()
  end

  defp api_user(scopes, name \\ "Other owner") do
    {_conn, user} = log_in_user(build_conn(), %{name: name, scopes: scopes})
    {put_req_header(build_conn(), "authorization", "Bearer #{oauth_access_token_fixture(user)}"), user}
  end

  defp invoice_attrs,
    do: %{
      vendor_name: "Manual vendor",
      invoice_number: "NATIVE-1",
      invoice_date: "2027-01-10",
      total_amount_value: "12.45",
      total_amount_currency: "EUR"
    }

  defp assert_audit(action, id, actor_id) do
    assert %Activity{actor_id: ^actor_id, interface: "api", metadata: %{"path" => path}} =
             Repo.one(from activity in Activity, where: activity.action == ^action and activity.target_id == ^id)

    assert is_binary(path)
  end

  defp endpoints do
    for resource <- ["tasks", "accounts", "invoices"],
        endpoint <- [
          {:get, "/api/native/#{resource}"},
          {:post, "/api/native/#{resource}"},
          {:get, "/api/native/#{resource}/unknown"},
          {:patch, "/api/native/#{resource}/unknown"},
          {:delete, "/api/native/#{resource}/unknown"},
          {:post, "/api/native/#{resource}/unknown/complete"}
        ],
        do: endpoint
  end
end

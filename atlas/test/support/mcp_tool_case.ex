defmodule Atlas.MCP.ToolCase do
  @moduledoc """
  Test case for MCP tool modules. Wraps `Atlas.DataCase` and exposes a
  small set of fixtures so each tool can be tested in its own module
  without duplicating insert helpers.

  Tests using this case always run with `async: true`; the option is set here
  rather than by each caller, so `use Atlas.MCP.ToolCase` needs no arguments.
  """

  use ExUnit.CaseTemplate

  alias Atlas.Accounts.Account
  alias Atlas.Accounts.AccountHandle
  alias Atlas.Accounts.Contact
  alias Atlas.Accounts.Event
  alias Atlas.Accounts.Invoice
  alias Atlas.MCP.Tool
  alias Atlas.Outreach.Candidate
  alias Atlas.Repo
  alias Atlas.Users.User

  using do
    quote do
      use Atlas.DataCase, async: true

      import Atlas.MCP.ToolCase
    end
  end

  @doc """
  Runs a tool's `execute/2` and, on success, pushes the payload through the same
  structured content validation the MCP server applies, which raises in test on any
  drift between a tool's declared `output_schema` and what it actually returns.

  Tool tests call this instead of `execute/2` so the declared schemas are exercised
  against real payloads rather than only asserted by hand.
  """
  def execute_tool(module, conn, args) do
    case module.execute(conn, args) do
      {:ok, payload} = result ->
        Tool.json_response(payload, module)
        result

      other ->
        other
    end
  end

  def insert_account!(attrs \\ %{}) do
    defaults = %{
      account_key: "account:#{System.unique_integer([:positive])}",
      name: "Account",
      segment: :lead
    }

    %Account{}
    |> Account.changeset(Map.merge(defaults, attrs))
    |> Repo.insert!()
  end

  def insert_user!(attrs \\ %{}) do
    defaults = %{
      email: "user-#{System.unique_integer([:positive])}@tuist.dev",
      name: "Test User"
    }

    %User{}
    |> User.changeset(Map.merge(defaults, attrs))
    |> Repo.insert!()
  end

  def mcp_conn(user), do: %{assigns: %{current_user: user}}

  def executive_mcp_conn do
    %{role: :executive}
    |> insert_user!()
    |> mcp_conn()
  end

  def insert_contact!(account, attrs \\ %{}) do
    defaults = %{
      full_name: "Contact #{System.unique_integer([:positive])}",
      email: "contact-#{System.unique_integer([:positive])}@example.com",
      account_id: account.id
    }

    %Contact{}
    |> Contact.outreach_changeset(Map.merge(defaults, attrs))
    |> Repo.insert!()
  end

  def insert_event!(account, attrs \\ %{}) do
    defaults = %{
      external_id: "event:#{System.unique_integer([:positive])}",
      source: "atlas",
      kind: "note",
      title: "Event",
      occurred_at: ~U[2025-01-01 00:00:00Z],
      account_id: account.id
    }

    %Event{}
    |> Event.changeset(Map.merge(defaults, attrs))
    |> Repo.insert!()
  end

  def insert_handle!(account, attrs \\ %{}) do
    defaults = %{
      handle: "handle-#{System.unique_integer([:positive])}",
      source: "slack",
      account_id: account.id
    }

    %AccountHandle{}
    |> AccountHandle.changeset(Map.merge(defaults, attrs))
    |> Repo.insert!()
  end

  def insert_invoice!(account, attrs \\ %{}) do
    defaults = %{
      external_id: "invoice:#{System.unique_integer([:positive])}",
      source: "stripe",
      number: "INV-#{System.unique_integer([:positive])}",
      due_date: ~D[2026-01-01],
      amount_value: Decimal.new("100.00"),
      amount_currency: "EUR",
      status: "open",
      stripe_url: "https://stripe.example/invoices/#{System.unique_integer([:positive])}"
    }

    %Invoice{account_id: account.id}
    |> Invoice.changeset(Map.merge(defaults, attrs))
    |> Repo.insert!()
  end

  def insert_outreach_candidate!(attrs \\ %{}) do
    suffix = System.unique_integer([:positive])

    defaults = %{
      source: "apollo",
      source_id: "apollo-candidate-#{suffix}",
      search_segment: "mobile_mid_large",
      search_version: 1,
      status: "pending",
      full_name: "Riley #{suffix}",
      title: "Head of Mobile",
      organization_name: "Search Platforms",
      organization_source_id: "organization-#{suffix}",
      organization_domain: "search-#{suffix}.example",
      linkedin_url: "https://www.linkedin.com/in/riley-#{suffix}",
      search_rank: 1,
      discovered_at: ~U[2026-07-20 12:00:00Z]
    }

    %Candidate{}
    |> Candidate.changeset(Map.merge(defaults, attrs))
    |> Repo.insert!()
  end

  def conn_for(user), do: %Plug.Conn{assigns: %{current_user: user}}
end

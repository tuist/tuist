defmodule TuistWeb.OpsAccountsLive do
  @moduledoc false
  use TuistWeb, :live_view
  use Noora

  import Ecto.Query, only: [from: 2]
  import TuistWeb.OpsAccountHelpers

  alias Tuist.Accounts
  alias Tuist.Billing.Subscription
  alias Tuist.Repo
  alias TuistWeb.Utilities.Query

  @page_size 30

  @impl true
  def mount(_params, _session, socket) do
    {:ok, assign(socket, :head_title, "Accounts · Tuist Ops")}
  end

  @impl true
  def handle_params(_params, uri, socket) do
    query_params = Query.query_params(uri)
    search = query_params["search"] || ""
    page = parse_page(query_params["page"])

    filters =
      case search do
        "" -> []
        term -> [%{field: :search, op: :==, value: term}]
      end

    {accounts, meta} =
      Accounts.list_accounts(%{
        page: page,
        page_size: @page_size,
        filters: filters
      })

    accounts =
      Repo.preload(accounts, [
        :organization,
        :user,
        subscriptions:
          from(s in Subscription,
            where: s.status in ["active", "trialing"],
            order_by: [desc: s.inserted_at]
          )
      ])

    {:noreply,
     socket
     |> assign(:query_params, query_params)
     |> assign(:search, search)
     |> assign(:current_page, page)
     |> assign(:accounts, accounts)
     |> assign(:meta, meta)}
  end

  @impl true
  def handle_event("search", %{"search" => search}, socket) do
    params =
      socket.assigns.query_params
      |> Map.put("search", search)
      |> Map.delete("page")

    {:noreply, push_patch(socket, to: ~p"/ops/accounts?#{params}")}
  end

  defp parse_page(nil), do: 1

  defp parse_page(value) do
    case Integer.parse(to_string(value)) do
      {page, _} when page > 0 -> page
      _ -> 1
    end
  end
end

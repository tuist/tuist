defmodule TuistWeb.OpsAccountKuraSizingLive do
  @moduledoc """
  Every sizing decision recorded for an account, newest first.
  """
  use TuistWeb, :live_view
  use Noora

  alias Tuist.Accounts
  alias Tuist.Kura
  alias TuistWeb.Utilities.Query

  @page_size 30

  @impl true
  def mount(%{"id" => account_id}, _session, socket) do
    case Accounts.get_account_by_id(parse_id(account_id)) do
      {:error, :not_found} ->
        {:ok,
         socket |> put_flash(:error, dgettext("dashboard", "Account not found.")) |> push_navigate(to: ~p"/ops/accounts")}

      {:ok, account} ->
        {:ok,
         socket
         |> assign(:head_title, "#{account.name} · #{dgettext("dashboard", "Sizing")} · Tuist Ops")
         |> assign(:account, account)}
    end
  end

  @impl true
  def handle_params(_params, uri, socket) do
    query_params = Query.query_params(uri)
    page = parse_page(query_params["page"])

    {decisions, meta} =
      Kura.paginate_claim_sizing_history(socket.assigns.account, %{page: page, page_size: @page_size})

    {:noreply,
     socket
     |> assign(:query_params, query_params)
     |> assign(:current_page, page)
     |> assign(:decisions, decisions)
     |> assign(:meta, meta)}
  end

  defp parse_id(id) do
    case Integer.parse(id) do
      {parsed, ""} -> parsed
      _ -> -1
    end
  end

  defp parse_page(nil), do: 1

  defp parse_page(value) do
    case Integer.parse(to_string(value)) do
      {page, _} when page > 0 -> page
      _ -> 1
    end
  end
end

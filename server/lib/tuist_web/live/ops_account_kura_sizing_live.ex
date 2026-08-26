defmodule TuistWeb.OpsAccountKuraSizingLive do
  @moduledoc """
  Every sizing decision recorded for an account, newest first.
  """
  use TuistWeb, :live_view
  use Noora

  alias Tuist.Accounts
  alias Tuist.Kura

  @per_page 50

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
         |> assign(:account, account)
         |> assign(:per_page, @per_page)
         |> assign_page(account, 1)}
    end
  end

  @impl true
  def handle_event("next_page", _params, socket) do
    {:noreply, assign_page(socket, socket.assigns.account, socket.assigns.page + 1)}
  end

  @impl true
  def handle_event("previous_page", _params, socket) do
    {:noreply, assign_page(socket, socket.assigns.account, max(socket.assigns.page - 1, 1))}
  end

  defp assign_page(socket, account, page) do
    total = Kura.claim_sizing_decision_count(account)
    decisions = Kura.claim_sizing_history_page(account, page, @per_page)

    socket
    |> assign(:page, page)
    |> assign(:total, total)
    |> assign(:decisions, decisions)
    |> assign(:last_page, max(ceil(total / @per_page), 1))
  end

  defp parse_id(id) do
    case Integer.parse(id) do
      {parsed, ""} -> parsed
      _ -> -1
    end
  end
end

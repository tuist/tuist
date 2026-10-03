defmodule AtlasWeb.AccountLive.InvoicesView do
  @moduledoc false

  alias Atlas.Accounts
  alias AtlasWeb.AccountLive.Formatters

  @page_size 5

  def build(account, page) do
    {source, invoices} =
      if Formatters.stripe_customer?(account) do
        {:stripe, Accounts.reconciled_stripe_invoices(account)}
      else
        {:local, Accounts.upcoming_invoices(account)}
      end

    total_pages = total_pages(invoices, @page_size)
    page = min(page, total_pages)

    %{
      source: source,
      status: :ok,
      invoices: paginate(invoices, page, @page_size),
      page: page,
      total_pages: total_pages
    }
  end

  def maybe_refresh(socket, account) do
    previous_customer = socket.assigns[:account] && socket.assigns.account.stripe_customer_id

    if previous_customer == account.stripe_customer_id do
      socket
    else
      Phoenix.Component.assign(socket, :invoices_view, build(account, socket.assigns[:invoices_page] || 1))
    end
  end

  def total_pages([], _page_size), do: 1
  def total_pages(items, page_size), do: ceil(length(items) / page_size)

  def paginate(items, page, page_size) do
    items
    |> Enum.drop((page - 1) * page_size)
    |> Enum.take(page_size)
  end
end

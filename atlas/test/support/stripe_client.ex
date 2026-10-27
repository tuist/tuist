defmodule Atlas.TestSupport.StripeClient do
  @moduledoc false

  alias Atlas.TestSupport.ProcessRegistry

  def put_list_invoices(response), do: ProcessRegistry.put({__MODULE__, :list_invoices}, response)

  def put_list_invoices(customer_id, response),
    do: ProcessRegistry.put({__MODULE__, :list_invoices, customer_id}, response)

  def put_list_invoices_by_status(response), do: ProcessRegistry.put({__MODULE__, :list_invoices_by_status}, response)

  def put_list_invoices_page(response), do: ProcessRegistry.put({__MODULE__, :list_invoices_page}, response)
  def put_create_draft_invoice(response), do: ProcessRegistry.put({__MODULE__, :create_draft_invoice}, response)
  def put_add_invoice_items(response), do: ProcessRegistry.put({__MODULE__, :add_invoice_items}, response)
  def put_update_invoice(response), do: ProcessRegistry.put({__MODULE__, :update_invoice}, response)
  def put_get_invoice(response), do: ProcessRegistry.put({__MODULE__, :get_invoice}, response)
  def put_get_customer(response), do: ProcessRegistry.put({__MODULE__, :get_customer}, response)
  def put_update_customer(response), do: ProcessRegistry.put({__MODULE__, :update_customer}, response)
  def put_search_customers(response), do: ProcessRegistry.put({__MODULE__, :search_customers}, response)
  def put_create_customer(response), do: ProcessRegistry.put({__MODULE__, :create_customer}, response)

  def put_list_invoices_page(fixture_key, response) when is_binary(fixture_key) do
    ProcessRegistry.put({__MODULE__, :list_invoices_page, fixture_key}, response)
  end

  def list_invoices(customer_id, opts \\ []) do
    case ProcessRegistry.get({__MODULE__, :list_invoices, customer_id}) do
      nil -> resolve(:list_invoices, {customer_id, opts})
      callback when is_function(callback, 1) -> callback.(opts)
      response -> response
    end
  end

  def list_invoices_by_status(status, opts \\ []) do
    resolve(:list_invoices_by_status, {status, opts})
  end

  def list_invoices_page(opts \\ []) do
    case resolve_page_fixture(opts) do
      :disabled ->
        resolve(:list_invoices_page, opts)

      response ->
        response
    end
  end

  defp resolve_page_fixture(opts) do
    case Keyword.get(opts, :fixture_key) do
      fixture_key when is_binary(fixture_key) and fixture_key != "" ->
        {__MODULE__, :list_invoices_page, fixture_key}
        |> ProcessRegistry.get()
        |> case do
          nil -> :disabled
          callback when is_function(callback, 1) -> callback.(opts)
          response -> response
        end

      _other ->
        :disabled
    end
  end

  defp resolve(function, args) do
    case ProcessRegistry.get({__MODULE__, function}) do
      nil -> :disabled
      callback when is_function(callback, 1) -> callback.(args)
      response -> response
    end
  end

  def create_draft_invoice(customer_id, attrs, opts \\ []) do
    resolve(:create_draft_invoice, {customer_id, attrs, opts})
  end

  def add_invoice_items(invoice_id, line_items, opts \\ []) do
    resolve(:add_invoice_items, {invoice_id, line_items, opts})
  end

  def update_invoice(invoice_id, attrs, opts \\ []) do
    resolve(:update_invoice, {invoice_id, attrs, opts})
  end

  def get_invoice(invoice_id, opts \\ []) do
    resolve(:get_invoice, {invoice_id, opts})
  end

  def get_customer(customer_id, opts \\ []) do
    resolve(:get_customer, {customer_id, opts})
  end

  def update_customer(customer_id, attrs, opts \\ []) do
    resolve(:update_customer, {customer_id, attrs, opts})
  end

  def search_customers(query, opts \\ []) do
    resolve(:search_customers, {query, opts})
  end

  def create_customer(attrs, opts \\ []) do
    resolve(:create_customer, {attrs, opts})
  end
end

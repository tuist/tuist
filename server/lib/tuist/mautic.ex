defmodule Tuist.Mautic do
  @moduledoc ~S"""
  An Elixir interface to interact with the Mautic API.
  """

  @base_url "https://marketing.tuist.dev/api"
  @default_page_limit 100

  def base_url do
    @base_url
  end

  def default_page_limit do
    @default_page_limit
  end

  def companies(opts \\ []) do
    {:ok, paginated("#{@base_url}/companies", & &1["companies"], opts)}
  end

  def create_company(company) do
    case Req.post!("#{@base_url}/companies/new",
           headers: %{"content-type" => ["application/json"]},
           json: company,
           auth: auth(),
           retry: retry()
         ) do
      %{status: status, body: body} when status in 200..299 -> {:ok, body}
      %{status: status, body: body} -> {:error, %{status: status, body: body}}
    end
  end

  def update_company(company_id, company) do
    case Req.patch!("#{@base_url}/companies/#{company_id}/edit",
           headers: %{"content-type" => ["application/json"]},
           json: company,
           auth: auth(),
           retry: retry()
         ) do
      %{status: status, body: body} when status in 200..299 -> {:ok, body}
      %{status: status, body: body} -> {:error, %{status: status, body: body}}
    end
  end

  def remove_company(company_id) do
    case Req.delete!("#{@base_url}/companies/#{company_id}/delete",
           headers: %{"content-type" => ["application/json"]},
           auth: auth(),
           retry: retry()
         ) do
      %{status: status} when status in 200..299 -> :ok
    end
  end

  def add_contact_to_company(contact_id, company_id) do
    case Req.post!("#{@base_url}/companies/#{company_id}/contact/#{contact_id}/add",
           headers: %{"content-type" => ["application/json"]},
           auth: auth(),
           retry: retry()
         ) do
      %{status: status} when status in 200..299 -> :ok
    end
  end

  def remove_contact_from_company(contact_id, company_id) do
    case Req.post!("#{@base_url}/companies/#{company_id}/contact/#{contact_id}/remove",
           headers: %{"content-type" => ["application/json"]},
           auth: auth(),
           retry: retry()
         ) do
      %{status: status} when status in 200..299 -> :ok
    end
  end

  def add_contact_to_segment(contact_id, segment_id) do
    case Req.post!("#{@base_url}/segments/#{segment_id}/contact/#{contact_id}/add",
           headers: %{"content-type" => ["application/json"]},
           auth: auth(),
           retry: retry()
         ) do
      %{status: status} when status in 200..299 -> :ok
      %{status: status} -> {:error, "Failed with status #{status}"}
    end
  end

  def add_email_to_segment(email, segment_id) do
    with {:ok, contact_id} <- find_or_create_contact_by_email(email),
         :ok <- add_contact_to_segment(contact_id, segment_id) do
      {:ok, contact_id}
    end
  end

  defp find_or_create_contact_by_email(email) do
    case Req.get!("#{@base_url}/contacts",
           params: %{search: email},
           auth: auth(),
           retry: retry()
         ) do
      %{status: 200, body: %{"contacts" => contacts}} when map_size(contacts) > 0 ->
        {contact_id, _contact} =
          Enum.find(contacts, fn {_id, contact} ->
            contact["fields"]["core"]["email"]["value"] == email
          end)

        {:ok, contact_id}

      %{status: 200} ->
        case create_contact(%{"email" => email}) do
          {:ok, %{"contact" => %{"id" => contact_id}}} -> {:ok, to_string(contact_id)}
          error -> error
        end

      %{status: status, body: body} ->
        {:error, %{status: status, body: body}}
    end
  end

  def contacts do
    {:ok, paginated("#{@base_url}/contacts", & &1["contacts"])}
  end

  def create_contact(contact) do
    case Req.post!("#{@base_url}/contacts/new",
           headers: %{"content-type" => ["application/json"]},
           json: contact,
           auth: auth(),
           retry: retry()
         ) do
      %{status: status, body: body} when status in 200..299 -> {:ok, body}
    end
  end

  def update_contact(contact_id, contact) do
    case Req.patch!("#{@base_url}/contacts/#{contact_id}/edit",
           headers: %{"content-type" => ["application/json"]},
           json: contact,
           auth: auth(),
           retry: retry()
         ) do
      %{status: status, body: body} when status in 200..299 -> {:ok, body}
    end
  end

  def remove_contact(contact_id) do
    case Req.delete!("#{@base_url}/contacts/#{contact_id}/delete",
           headers: %{"content-type" => ["application/json"]},
           auth: auth(),
           retry: retry()
         ) do
      %{status: status} when status in 200..299 -> :ok
    end
  end

  def remove_contacts(contact_ids) do
    contact_ids
    |> Enum.chunk_every(200)
    |> Enum.reduce_while(:ok, fn batch, _acc ->
      batch
      |> remove_contacts_batch()
      |> case do
        :ok -> {:cont, :ok}
        error -> {:halt, error}
      end
    end)
  end

  defp remove_contacts_batch(batch) do
    %{status: status} =
      Req.delete!(
        "#{@base_url}/contacts/batch/delete",
        headers: %{"content-type" => ["application/json"]},
        json: batch,
        auth: auth(),
        retry: retry()
      )

    if status in 200..299, do: :ok, else: {:error, %{status: status}}
  end

  def create_contacts(contacts) do
    contacts
    |> Enum.chunk_every(200)
    |> Enum.each(fn batch ->
      case Req.post!("#{@base_url}/contacts/batch/new",
             headers: %{"content-type" => ["application/json"]},
             json: batch,
             auth: auth(),
             retry: retry()
           ) do
        %{status: status} when status in 200..299 -> :ok
      end
    end)
  end

  defp paginated(url, parser, opts \\ []) do
    page = Keyword.get(opts, :page, 0)
    page_limit = Keyword.get(opts, :page_limit, @default_page_limit)

    %{status: 200, body: body} =
      Req.get!(url,
        params: %{limit: page_limit, start: page * page_limit},
        auth: auth(),
        retry: retry()
      )

    results = parser.(body)

    if map_size(results) < page_limit do
      results
    else
      Map.merge(results, paginated(url, parser, Keyword.put(opts, :page, page + 1)))
    end
  end

  defp auth do
    {:basic, "#{Tuist.Environment.mautic_username()}:#{Tuist.Environment.mautic_password()}"}
  end

  defp retry do
    :safe_transient
  end
end

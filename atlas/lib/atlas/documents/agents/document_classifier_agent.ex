defmodule Atlas.Documents.Agents.DocumentClassifierAgent do
  @moduledoc false

  use Condukt

  alias Atlas.Agents.Sessions
  alias Atlas.Agents.StyleGuide
  alias Atlas.Documents
  alias Atlas.Documents.Document
  alias Atlas.LLMs.Runner

  @sample_page_limit 3
  @page_character_limit 1_500

  @impl true
  def tools do
    [
      list_tool(
        "list_correspondents",
        "List the correspondents (organizations or people) already in the library. Call this before deciding on a correspondent so you can reuse an existing one.",
        &Documents.correspondents/0
      ),
      list_tool(
        "list_document_types",
        "List the document types already in the library. Call this before deciding on a type so you can reuse an existing one.",
        &Documents.document_types/0
      ),
      list_tool(
        "list_tags",
        "List the tags already in the library. Call this before tagging so you can reuse existing labels.",
        &Documents.tags/0
      ),
      create_tool(
        "create_correspondent",
        "Create a correspondent, or return the closest existing one if a near-duplicate already exists. Only call this when no listed correspondent fits. Use the name it returns.",
        &Documents.resolve_correspondent/1
      ),
      create_tool(
        "create_document_type",
        "Create a document type, or return the closest existing one. Only call this when no listed type fits. Use the name it returns.",
        &Documents.resolve_document_type/1
      ),
      create_tool(
        "create_tag",
        "Create a tag, or return the closest existing one. Only call this when no listed tag fits. Use the name it returns.",
        &Documents.resolve_tag/1
      )
    ]
  end

  @impl true
  def system_prompt do
    """
    You classify internal company documents imported into Atlas.

    The library normalizes correspondents, document types, and tags so they are
    reused across documents instead of duplicated. Before assigning any of them:

    1. Call list_correspondents, list_document_types, and list_tags to see what
       already exists.
    2. Reuse an existing entry whenever it reasonably fits, even if the wording
       differs slightly. Prefer reuse over creating something new.
    3. Only when nothing existing fits, call the matching create_* tool. It
       returns the canonical name to use (which may be an existing close match it
       found). Always use the exact names the tools return in your final answer.

    Return concise metadata grounded only in the document text:
    - title: human-readable title
    - document_type: one stable snake_case type such as contract, invoice, policy,
      tax, legal, report, board, employment, other
    - correspondent: the organization or person the document is from or addressed to
      (for example a vendor, customer, bank, or authority). Use a clean proper name.
    - document_date: the date the document itself was issued or signed, as YYYY-MM-DD.
      Use the document's own date, not today's date.
    - tags: a short list (at most five) of lowercase topical labels such as security,
      finance, payroll, gdpr, soc2, renewal. Prefer reusing common labels.
    - summary: 1-2 sentence executive summary
    - attributes: object with any other useful searchable values like amount, currency,
      jurisdiction, effective_date, renewal_notice_days

    Do not invent missing values. Prefer omitting a field over guessing.

    #{StyleGuide.prose_rules()}
    """
  end

  def classify(%Document{} = document, pages) when is_list(pages) do
    case Runner.fetch_config() do
      {:ok, llm} ->
        Sessions.run(
          __MODULE__,
          prompt(document, pages),
          Runner.client_opts(llm) ++
            [
              max_turns: 8,
              load_project_instructions: false,
              output: output_schema()
            ]
        )
        |> normalize_result(document)

      {:error, :llm_not_configured} ->
        {:error, :llm_not_configured}
    end
  end

  @doc """
  Filename-derived metadata used when the LLM classifier is unavailable or
  fails. Lets ingest finish (text + embeddings) with degraded metadata rather
  than leaving the document unprocessed.
  """
  def fallback_metadata(%Document{} = document), do: fallback(document)

  defp list_tool(name, description, lister) do
    Condukt.tool(
      name: name,
      description: description,
      parameters: %{type: "object", properties: %{}},
      call: fn _params, _ctx ->
        {:ok, %{names: Enum.map(lister.(), & &1.name)}}
      end
    )
  end

  defp create_tool(name, description, resolver) do
    Condukt.tool(
      name: name,
      description: description,
      parameters: %{
        type: "object",
        required: ["name"],
        properties: %{
          name: %{type: "string", minLength: 1, description: "Clean proper name to find or create."}
        }
      },
      call: fn params, _ctx ->
        case resolver.(params["name"]) do
          nil -> {:error, "Provide a non-empty name."}
          record -> {:ok, %{name: record.name}}
        end
      end
    )
  end

  defp normalize_result({:ok, result}, document) when is_map(result) do
    {:ok,
     %{
       title: clean_string(result["title"] || result[:title]) || document.title,
       document_type: clean_type(result["document_type"] || result[:document_type]),
       correspondent: clean_string(result["correspondent"] || result[:correspondent]),
       document_date: parse_date(result["document_date"] || result[:document_date]),
       tags: clean_tags(result["tags"] || result[:tags]),
       summary: clean_string(result["summary"] || result[:summary]),
       attributes: clean_attributes(result["attributes"] || result[:attributes])
     }}
  end

  defp normalize_result({:ok, _other}, _document), do: {:error, :invalid_classifier_output}
  defp normalize_result({:error, reason}, _document), do: {:error, reason}

  defp fallback(%Document{} = document) do
    %{
      title: document.title,
      document_type: type_from_filename(document.original_filename),
      correspondent: nil,
      document_date: nil,
      tags: [],
      summary: nil,
      attributes: %{}
    }
  end

  defp prompt(document, pages) do
    sample =
      pages
      |> Enum.take(@sample_page_limit)
      |> Enum.map_join("\n\n", fn page ->
        "Page #{page.page_number}:\n#{String.slice(page.content, 0, @page_character_limit)}"
      end)

    """
    Classify this document.

    Filename: #{document.original_filename}
    Current title: #{document.title}

    Text sample:
    #{sample}
    """
  end

  defp output_schema do
    %{
      type: "object",
      properties: %{
        title: %{type: "string"},
        document_type: %{type: "string"},
        correspondent: %{type: "string"},
        document_date: %{type: "string"},
        tags: %{type: "array", items: %{type: "string"}},
        summary: %{type: "string"},
        attributes: %{type: "object"}
      },
      required: ["title", "document_type"]
    }
  end

  defp type_from_filename(filename) do
    filename = String.downcase(filename || "")

    cond do
      String.contains?(filename, "invoice") -> "invoice"
      String.contains?(filename, "contract") -> "contract"
      String.contains?(filename, "agreement") -> "contract"
      String.contains?(filename, "tax") -> "tax"
      true -> "other"
    end
  end

  defp clean_string(value) when is_binary(value) do
    value = String.trim(value)
    if value != "", do: value
  end

  defp clean_string(_value), do: nil

  defp clean_type(value) do
    value
    |> clean_string()
    |> case do
      nil -> "other"
      type -> type |> String.downcase() |> String.replace(~r/[^a-z0-9]+/, "_") |> String.trim("_")
    end
  end

  defp clean_tags(values) when is_list(values) do
    values
    |> Enum.map(&clean_tag/1)
    |> Enum.reject(&is_nil/1)
    |> Enum.uniq()
    |> Enum.take(5)
  end

  defp clean_tags(_values), do: []

  defp clean_tag(value) do
    value
    |> clean_string()
    |> case do
      nil -> nil
      tag -> tag |> String.downcase() |> String.replace(~r/[^a-z0-9]+/, "_") |> String.trim("_")
    end
    |> case do
      nil -> nil
      "" -> nil
      tag -> tag
    end
  end

  defp parse_date(value) when is_binary(value) do
    case Date.from_iso8601(String.trim(value)) do
      {:ok, date} -> date
      {:error, _reason} -> nil
    end
  end

  defp parse_date(%Date{} = date), do: date
  defp parse_date(_value), do: nil

  defp clean_attributes(value) when is_map(value) do
    value
    |> Enum.filter(fn {key, value} -> is_binary(to_string(key)) and present_attribute?(value) end)
    |> Map.new(fn {key, value} -> {to_string(key), value} end)
  end

  defp clean_attributes(_value), do: %{}

  defp present_attribute?(nil), do: false
  defp present_attribute?(""), do: false
  defp present_attribute?(_value), do: true
end

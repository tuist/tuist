defmodule Atlas.Product do
  @moduledoc """
  Authoritative product activity captured from configured GitHub repositories.
  """

  import Ecto.Query

  alias Atlas.Audit
  alias Atlas.Product.Trace
  alias Atlas.Repo

  @default_page_size 50
  @max_page_size 100

  def record_trace(attrs) when is_map(attrs) do
    changeset = Trace.changeset(%Trace{}, attrs)

    changeset
    |> Repo.insert(
      on_conflict: {:replace, [:title, :url, :author_login, :occurred_at, :labels, :sensitivity]},
      conflict_target: [:provider, :external_id],
      returning: true
    )
    |> tap(fn
      {:ok, trace} -> audit_trace(trace)
      _result -> :ok
    end)
  end

  def get_trace(id) when is_binary(id) do
    Trace
    |> preload(:github_repository)
    |> Repo.get(id)
  end

  def list_traces(opts \\ []) do
    page_size = opts |> Keyword.get(:page_size, @default_page_size) |> min(@max_page_size) |> max(1)
    offset = max(Keyword.get(opts, :offset, 0), 0)

    query =
      Trace
      |> maybe_filter(:kind, Keyword.get(opts, :kind))
      |> maybe_filter(:github_repository_id, Keyword.get(opts, :github_repository_id))
      |> maybe_after(Keyword.get(opts, :after))
      |> maybe_before(Keyword.get(opts, :before))
      |> order_by([trace], desc: trace.occurred_at, desc: trace.id)
      |> preload(:github_repository)

    Flop.run(query, %Flop{limit: page_size, offset: offset}, for: Trace)
  end

  defp maybe_filter(query, _field, nil), do: query
  defp maybe_filter(query, field, value), do: where(query, [trace], field(trace, ^field) == ^value)
  defp maybe_after(query, nil), do: query
  defp maybe_after(query, value), do: where(query, [trace], trace.occurred_at >= ^value)
  defp maybe_before(query, nil), do: query
  defp maybe_before(query, value), do: where(query, [trace], trace.occurred_at < ^value)

  defp audit_trace(trace) do
    Audit.record(
      "product_trace.recorded",
      %{
        target_type: "product_trace",
        target_id: trace.id,
        target_label: "#{trace.repository_full_name} ##{trace.number}: #{trace.title}",
        metadata: %{
          "kind" => trace.kind,
          "repository" => trace.repository_full_name,
          "url" => trace.url
        }
      },
      interface: "worker"
    )
  end
end

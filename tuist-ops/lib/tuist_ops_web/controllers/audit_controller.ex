defmodule TuistOpsWeb.AuditController do
  @moduledoc """
  The audit trail: one page with two sections (tabs), each a paginated
  table.

    * `?section=cluster`  — Tailscale JIT elevations.
    * `?section=projects` — customer project-access requests.
  """
  use TuistOpsWeb, :controller

  alias TuistOps.Audit

  @sections ~w(cluster projects)

  def root(conn, _params), do: redirect(conn, to: ~p"/audit")

  def index(conn, params) do
    section = if params["section"] in @sections, do: params["section"], else: "cluster"
    page = parse_page(params["page"])
    {requests, count} = load(section, page)

    render(conn, :index,
      section: section,
      requests: requests,
      page: page,
      total_pages: Audit.total_pages(count)
    )
  end

  defp load("projects", page), do: {Audit.project_page(page), Audit.project_count()}
  defp load(_cluster, page), do: {Audit.cluster_page(page), Audit.cluster_count()}

  defp parse_page(value) when is_binary(value) do
    case Integer.parse(value) do
      {page, _} when page >= 1 -> page
      _ -> 1
    end
  end

  defp parse_page(_), do: 1
end

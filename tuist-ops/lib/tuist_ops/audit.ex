defmodule TuistOps.Audit do
  @moduledoc """
  Read model for the audit pages: the two access surfaces this app
  governs, newest first, paginated.

    * Cluster access — Tailscale JIT elevations (`tailscale_jit_requests`).
    * Customer project access — operator access requests
      (`project_access_requests`).
  """

  import Ecto.Query, only: [from: 2]

  alias TuistOps.JIT.Request, as: JitRequest
  alias TuistOps.ProjectAccess.Request, as: ProjectAccessRequest
  alias TuistOps.Repo

  @per_page 25

  def per_page, do: @per_page

  def total_pages(count), do: max(ceil(count / @per_page), 1)

  def cluster_count, do: Repo.aggregate(JitRequest, :count)
  def cluster_page(page), do: page(JitRequest, page)

  def project_count, do: Repo.aggregate(ProjectAccessRequest, :count)
  def project_page(page), do: page(ProjectAccessRequest, page)

  defp page(schema, page) do
    page = max(page, 1)
    offset = (page - 1) * @per_page

    Repo.all(
      from(r in schema, order_by: [desc: r.inserted_at], limit: ^@per_page, offset: ^offset)
    )
  end
end

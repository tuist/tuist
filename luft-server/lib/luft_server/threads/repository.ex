defmodule LuftServer.Threads.Repository do
  @moduledoc "Repository operations brokered by Tuist; credentials never leave its server."
  alias LuftServer.Threads.Capabilities

  def authorize(owner, name, level \\ :read) do
    with {:ok, data} <-
           Capabilities.request(owner, "repository_authorize", %{
             repository: name,
             level: Atom.to_string(level)
           }) do
      {:ok, %{name: data["name"], default_branch: data["default_branch"], size: data["size"]}}
    end
  end

  def branch_head(owner, repository, branch),
    do: Capabilities.request(owner, "repository_head", %{repository: repository, branch: branch})

  def review(owner, snapshot, objects),
    do:
      Capabilities.request(owner, "repository_review", %{
        repository: snapshot.repository,
        snapshot: snapshot(snapshot),
        objects: objects
      })

  def reconcile(owner, approval) do
    case Capabilities.request(owner, "publication_reconcile", %{
           repository: approval.repository,
           request_id: approval.request_id
         }) do
      {:ok, %{"request_id" => id, "head_sha" => head, "target_branch" => branch}}
      when id == approval.request_id and head == approval.head_sha and
             branch == approval.target_branch ->
        :ok

      _ ->
        {:error, :shipping_uncertain}
    end
  end

  def publish(owner, approval, objects),
    do:
      Capabilities.request(owner, "repository_publish", %{
        repository: approval.repository,
        request_id: approval.request_id,
        snapshot: snapshot(approval),
        mode: Atom.to_string(approval.mode),
        objects: objects,
        diff: approval.diff
      })

  defp snapshot(snapshot),
    do:
      snapshot
      |> Map.take([:base_sha, :head_sha, :target_branch])
      |> Map.put(:operation_id, snapshot.thread_id)
end

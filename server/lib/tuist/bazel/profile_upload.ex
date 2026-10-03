defmodule Tuist.Bazel.ProfileUpload do
  @moduledoc "Durable staging for bounded profile processing outside webhook requests."
  use Ecto.Schema

  import Ecto.Query

  alias Ecto.Multi
  alias Tuist.Bazel.Workers.ProcessProfileWorker
  alias Tuist.Repo

  @primary_key false
  schema "bazel_profile_uploads" do
    field :project_id, :integer, primary_key: true
    field :invocation_id, :string, primary_key: true
    field :compressed, :binary
    field :state, :string
    field :error, :string
    timestamps(type: :utc_datetime)
  end

  def stage(project, id, compressed) when byte_size(compressed) <= 32 * 1024 * 1024 do
    now = DateTime.truncate(DateTime.utc_now(), :second)

    Multi.new()
    |> Multi.insert_all(
      :upload,
      __MODULE__,
      [
        %{
          project_id: project.id,
          invocation_id: id,
          compressed: compressed,
          state: "pending",
          inserted_at: now,
          updated_at: now
        }
      ],
      conflict_target: [:project_id, :invocation_id],
      on_conflict:
        from(u in __MODULE__,
          where: u.state in ["rejected", "failed"],
          update: [set: [compressed: ^compressed, state: "pending", error: nil, updated_at: ^now]]
        )
    )
    |> Multi.run(:job, fn _repo, %{upload: {count, _}} ->
      if count == 1 do
        Oban.insert(ProcessProfileWorker.new(%{project_id: project.id, invocation_id: id}))
      else
        {:ok, :unchanged}
      end
    end)
    |> Repo.transaction()
    |> case do
      {:ok, _} -> :ok
      {:error, _, reason, _} -> {:error, reason}
    end
  end

  def stage(_, _, _), do: {:error, :profile_too_large}

  def query(project_id, id), do: from(u in __MODULE__, where: u.project_id == ^project_id and u.invocation_id == ^id)

  def state(%{project_id: nil}), do: nil
  def state(%{invocation_id: nil}), do: nil

  def state(invocation) do
    Repo.one(from(u in query(invocation.project_id, invocation.invocation_id), select: u.state))
  end

  def expire(before, limit) do
    expired =
      from(u in __MODULE__,
        where: u.inserted_at < ^before,
        limit: ^limit,
        select: %{project_id: u.project_id, invocation_id: u.invocation_id}
      )

    {count, _} =
      Repo.delete_all(
        from(u in __MODULE__,
          join: e in subquery(expired),
          on: u.project_id == e.project_id and u.invocation_id == e.invocation_id
        )
      )

    count
  end
end

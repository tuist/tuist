defmodule Tuist.Runners.ConcurrencyHistory do
  @moduledoc """
  Effective runner limits, recorded atomically by PostgreSQL on every change.
  History starts at deployment's baseline; older limits are unknown.
  """
  use Ecto.Schema

  import Ecto.Query

  alias Tuist.Repo

  schema "runner_concurrency_history" do
    field :account_id, :integer
    field :platform, Ecto.Enum, values: [:linux, :macos]
    field :vcpus, :integer
    field :memory_gb, :integer
    field :source, :string
    field :reason, :string
    field :recorded_at, :utc_datetime_usec
  end

  @doc """
  The last known value at the start plus all changes through the end, oldest
  first. The platform/id ordering resolves updates sharing a timestamp.
  """
  def between(account_id, from, to) do
    baseline =
      __MODULE__
      |> where([h], h.account_id == ^account_id and h.recorded_at < ^from)
      |> distinct([h], h.platform)
      |> order_by([h], asc: h.platform, desc: h.recorded_at, desc: h.id)
      |> Repo.all()

    changes =
      __MODULE__
      |> where([h], h.account_id == ^account_id and h.recorded_at >= ^from and h.recorded_at <= ^to)
      |> order_by([h], asc: h.recorded_at, asc: h.id)
      |> Repo.all()

    baseline ++ changes
  end

  def at(history, platform, %Date{} = date), do: at(history, platform, DateTime.new!(date, ~T[00:00:00], "Etc/UTC"))

  def at(history, platform, %DateTime{} = instant) do
    history
    |> Enum.filter(&(&1.platform == platform and not DateTime.after?(&1.recorded_at, instant)))
    |> List.last()
  end

  def series(history, dates) do
    Map.new([:linux, :macos], fn platform ->
      limits = Enum.map(dates, &at(history, platform, &1))

      {platform,
       %{
         vcpus: Enum.map(limits, &(&1 && &1.vcpus)),
         memory_gb: Enum.map(limits, &(&1 && &1.memory_gb))
       }}
    end)
  end
end

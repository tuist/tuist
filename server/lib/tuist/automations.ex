defmodule Tuist.Automations do
  @moduledoc false
  import Ecto.Query

  alias Tuist.Automations.Automation
  alias Tuist.Automations.AutomationTrigger
  alias Tuist.ClickHouseRepo
  alias Tuist.IngestRepo
  alias Tuist.Repo

  def list_automations(project_id) do
    Automation
    |> where(project_id: ^project_id)
    |> order_by(asc: :inserted_at)
    |> Repo.all()
  end

  def get_automation(id) do
    case Repo.get(Automation, id) do
      nil -> {:error, :not_found}
      automation -> {:ok, automation}
    end
  end

  def create_automation(attrs) do
    %Automation{}
    |> Automation.changeset(attrs)
    |> Repo.insert()
  end

  def update_automation(%Automation{} = automation, attrs) do
    automation
    |> Automation.changeset(attrs)
    |> Repo.update()
  end

  def delete_automation(%Automation{} = automation) do
    Repo.delete(automation)
  end

  @doc """
  Returns currently active triggers for an automation (latest status = "triggered").
  Uses argMax to find the most recent status per test_case_id from the append-only log.
  """
  def list_triggers(automation_id) do
    ClickHouseRepo.all(
      from(t in AutomationTrigger,
        where: t.automation_id == ^automation_id,
        group_by: t.test_case_id,
        having: fragment("argMax(?, ?) = 'triggered'", t.status, t.inserted_at),
        select: %{
          test_case_id: t.test_case_id,
          triggered_at: fragment("argMax(?, ?)", t.triggered_at, t.inserted_at)
        }
      )
    )
  end

  @doc """
  Appends a trigger event to the log.
  """
  def insert_trigger(attrs) do
    now = NaiveDateTime.utc_now()

    record =
      attrs
      |> Map.put_new(:id, UUIDv7.generate())
      |> Map.put_new(:inserted_at, now)

    IngestRepo.insert_all(AutomationTrigger, [record])
    :ok
  end

  @doc """
  Appends a recovery event to the log. Simple insert, no read needed.
  """
  def mark_recovered(automation_id, test_case_id) do
    insert_trigger(%{
      automation_id: automation_id,
      test_case_id: test_case_id,
      status: "recovered",
      triggered_at: NaiveDateTime.utc_now(),
      recovered_at: NaiveDateTime.utc_now()
    })
  end
end

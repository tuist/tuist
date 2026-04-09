defmodule Tuist.Automations do
  @moduledoc false
  import Ecto.Query

  alias Tuist.Automations.Automation
  alias Tuist.Automations.AutomationState
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

  def list_triggered_states(automation_id) do
    ClickHouseRepo.all(
      from(s in AutomationState, hints: ["FINAL"], where: s.automation_id == ^automation_id and s.status == "triggered")
    )
  end

  def get_triggered_state(automation_id, test_case_id) do
    ClickHouseRepo.one(
      from(s in AutomationState,
        hints: ["FINAL"],
        where: s.automation_id == ^automation_id and s.test_case_id == ^test_case_id and s.status == "triggered"
      )
    )
  end

  def insert_automation_state(attrs) do
    now = NaiveDateTime.utc_now()

    record =
      attrs
      |> Map.put_new(:id, UUIDv7.generate())
      |> Map.put_new(:inserted_at, now)

    IngestRepo.insert_all(AutomationState, [record])
    :ok
  end

  def mark_recovered(automation_id, test_case_id) do
    case get_triggered_state(automation_id, test_case_id) do
      nil ->
        :ok

      state ->
        now = NaiveDateTime.utc_now()

        recovered =
          state
          |> Map.from_struct()
          |> Map.delete(:__meta__)
          |> Map.merge(%{
            status: "recovered",
            recovered_at: now,
            inserted_at: now
          })

        IngestRepo.insert_all(AutomationState, [recovered])
        :ok
    end
  end
end

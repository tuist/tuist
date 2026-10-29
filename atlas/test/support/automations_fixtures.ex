defmodule Atlas.AutomationsFixtures do
  @moduledoc false

  alias Atlas.Automations

  def workflow_fixture(actor, steps \\ nil) do
    steps = steps || [%{"id" => "value", "behavior" => "core.value", "inputs" => %{"message" => "Hello"}}]

    {:ok, workflow} =
      Automations.create_workflow(actor, %{
        "name" => "Workflow #{System.unique_integer([:positive])}",
        "source" => JSON.encode!(%{"steps" => steps})
      })

    {:ok, revision} = Automations.publish_workflow(actor, workflow.id)
    {workflow, revision}
  end
end

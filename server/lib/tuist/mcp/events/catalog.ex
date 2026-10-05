defmodule Tuist.MCP.Events.Catalog do
  @moduledoc false

  @project_events ["test_case.marked_flaky", "build.failed", "test_run.failed"]
  @account_events ["ci_job.failed"]

  def supported?(name), do: name in @project_events or name in @account_events

  def target("build.failed"), do: {:project, :build}
  def target(name) when name in @project_events, do: {:project, :test}
  def target(name) when name in @account_events, do: {:account, :runners}
  def target(_name), do: nil

  def list do
    %{
      "events" => [
        descriptor("test_case.marked_flaky", "A test case in the selected project was marked flaky.", project_schema(), [
          "test_case_id"
        ]),
        descriptor("build.failed", "A build in the selected project failed.", project_schema(), [
          "build_id",
          "build_system"
        ]),
        descriptor("test_run.failed", "A test run in the selected project failed.", project_schema(), ["test_run_id"]),
        descriptor(
          "ci_job.failed",
          "A continuous integration runner job in the selected account failed.",
          account_schema(),
          ["workflow_job_id", "workflow_run_id"]
        )
      ]
    }
  end

  defp project_schema do
    %{
      "type" => "object",
      "properties" => %{
        "account_handle" => %{"type" => "string"},
        "project_handle" => %{"type" => "string"}
      },
      "required" => ["account_handle", "project_handle"],
      "additionalProperties" => false
    }
  end

  defp account_schema do
    %{
      "type" => "object",
      "properties" => %{"account_handle" => %{"type" => "string"}},
      "required" => ["account_handle"],
      "additionalProperties" => false
    }
  end

  defp descriptor(name, description, input_schema, fields) do
    properties =
      fields
      |> Enum.reduce(%{"account_handle" => %{"type" => "string"}, "url" => %{"type" => "string"}}, fn
        field, acc ->
          Map.put(acc, field, %{
            "type" => if(field in ["workflow_job_id", "workflow_run_id"], do: "integer", else: "string")
          })
      end)
      |> then(fn props ->
        if name == "ci_job.failed", do: props, else: Map.put(props, "project_handle", %{"type" => "string"})
      end)

    %{
      "name" => name,
      "description" => description,
      "delivery" => ["webhook"],
      "inputSchema" => input_schema,
      "payloadSchema" => %{
        "type" => "object",
        "properties" => properties,
        "required" => Map.keys(properties),
        "additionalProperties" => false
      }
    }
  end
end

defmodule Tuist.RemoteExecution.Schemas do
  @moduledoc "Shared HTTP and MCP contracts for a project's remote execution activity and usage."
  alias OpenApiSpex.Schema

  def activity do
    object(
      "RemoteExecutionActivity",
      %{
        observed_at: timestamp("When the scheduler was read."),
        running: integer("Actions executing in a VM."),
        queued: integer("Actions waiting for a VM."),
        actions:
          array(
            object("RemoteExecutionActiveAction", %{
              state: %Schema{
                type: :string,
                description: "`running` or `queued`. Open string: more states can be added."
              },
              action_digest: string("The REAPI action digest as `hash/size`."),
              invocation_id:
                nullable(string("The Bazel invocation that requested the action, from its request metadata.")),
              mnemonic: nullable(string("The action's mnemonic, such as `CppCompile`.")),
              target: nullable(string("The label of the target the action belongs to.")),
              vcpus: integer("vCPUs of the VM the action runs or will run in."),
              memory_gb: integer("Memory in GB of the VM the action runs or will run in."),
              since: timestamp("When the action entered its current state.")
            })
          ),
        invocations:
          array(
            object(
              "RemoteExecutionRunningInvocation",
              %{
                invocation_id: string("The Bazel invocation ID."),
                command: nullable(string("The Bazel command, or null while the build event stream has not reported it.")),
                target_patterns: array(string("A requested target pattern.")),
                git_branch: string("The Git branch, or empty when not reported."),
                git_commit_sha: string("The Git commit, or empty when not reported."),
                is_ci: nullable(%Schema{type: :boolean, description: "Whether it runs on CI; null when unknown."}),
                started_at: timestamp("When the invocation started."),
                running: integer("Its remote actions executing in a VM."),
                queued: integer("Its remote actions waiting for a VM.")
              },
              "An invocation that started in the last 24 hours and has not finished."
            )
          )
      },
      "Running actions first, each group oldest first. Actions the execution gateway runs on a VM it holds in " <>
        "advance are not listed; they appear in usage once they finish. `invocations` lists the running Bazel " <>
        "invocations, newest first."
    )
  end

  def usage do
    totals = %{executions: integer("Executions that ran in a VM."), execution_ms: integer("Measured execution time.")}

    object(
      "RemoteExecutionUsage",
      Map.merge(totals, %{
        from: timestamp("Start of the period, inclusive."),
        to: timestamp("End of the period, exclusive."),
        granularity: string("Bucket size of `series`: `hour`, `day` or `month`."),
        shapes:
          array(
            object(
              "RemoteExecutionUsageShape",
              Map.merge(totals, %{
                vcpus: integer("vCPUs of the VM shape."),
                memory_gb: integer("Memory in GB of the VM shape.")
              })
            )
          ),
        modes:
          array(
            object(
              "RemoteExecutionUsageMode",
              Map.put(
                totals,
                :mode,
                string(
                  "How the action reached its VM: `scheduled` by the account's scheduler or `leased` to the execution gateway. Open string."
                )
              )
            )
          ),
        series:
          array(
            object(
              "RemoteExecutionUsagePoint",
              Map.put(totals, :bucket, string("The bucket's start in UTC, formatted for its granularity."))
            )
          )
      }),
      "Executions recorded by the execution node, with the time the executor ran in each single-use VM, " <>
        "from its start to its exit. It includes fetching inputs and uploading outputs, not queueing or " <>
        "preparing the VM. Results served from the cache are not executions. Every bucket of the period is listed."
    )
  end

  def usage_inputs do
    %{
      from: %Schema{
        type: :string,
        format: :"date-time",
        description: "Start of the period, inclusive. Defaults to 30 days before `to`."
      },
      to: %Schema{type: :string, format: :"date-time", description: "End of the period, exclusive. Defaults to now."}
    }
  end

  defp object(title, fields, description \\ nil),
    do: %Schema{
      title: title,
      description: description,
      type: :object,
      properties: fields,
      required: Enum.sort(Map.keys(fields)),
      additionalProperties: false
    }

  defp nullable(schema), do: %{schema | nullable: true}
  defp array(items), do: %Schema{type: :array, items: items}
  defp string(description), do: %Schema{type: :string, description: description}
  defp integer(description), do: %Schema{type: :integer, description: description}
  defp timestamp(description), do: %Schema{type: :string, format: :"date-time", description: description}
end

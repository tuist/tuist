defmodule LuftServer.Workspaces.Authoring do
  @moduledoc "Run-fenced authoring tools using the triggering human's current delegation."

  alias LuftServer.Threads
  alias LuftServer.Workspaces.BehaviorDefinition
  alias LuftServer.Workspaces.Behaviors
  alias LuftServer.Workspaces.Records

  def tools(run) do
    proposal = %{
      type: "object",
      properties: %{
        baseline: %{type: ["string", "null"], pattern: "^[a-f0-9]{64}$"},
        definition: BehaviorDefinition.authoring_schema()
      },
      required: ["baseline", "definition"],
      additionalProperties: false
    }

    hash = %{type: "string", pattern: "^[a-f0-9]{64}$"}

    [
      Condukt.tool(
        name: "inspect_behaviors",
        description:
          "Read the installed behavior definition, active baseline, authoring schema and sandbox constraints before authoring. Requires the triggering author's current author role. Returns authored code, never resource rows. Definitions and tool inputs enter this conversation; never include secrets or private record snapshots.",
        parameters: %{type: "object", properties: %{}, additionalProperties: false},
        call: fn args, _ -> request(run, :authoring, args) end,
        replay_safe: true,
        read_only: true
      ),
      Condukt.tool(
        name: "validate_behavior_release",
        description:
          "Check a complete proposed definition against inspect_behaviors' current baseline and compile every JavaScript method in the bounded sandbox. Returns valid, repair diagnostics, compatibility, exact changes and blockers. Does not execute methods, test business behavior, persist a proposal, approve or activate it.",
        parameters: proposal,
        call: fn args, _ -> request(run, :validate, args) end,
        replay_safe: true,
        read_only: true
      ),
      Condukt.tool(
        name: "propose_behavior_release",
        description:
          "Create an ops proposal branch for independent human review after validation. Returns its immutable hash, baseline, base_commit_id and commit_id; main, active behavior and permissions do not change. Repeated content against the same main and baseline returns the same proposal. If main moves, repropose for fresh review. Review is in Profile → Releases; this result is not approval, merge or activation.",
        parameters: proposal,
        call: fn args, _ -> request(run, :propose, args) end,
        replay_safe: true
      ),
      Condukt.tool(
        name: "inspect_behavior_releases",
        description:
          "Inspect review status under current author, reviewer or activator permissions. Omit hash to list the latest 20 proposals and active hash; supply a returned hash for the exact definition, baseline, changes and current activation blockers. Use this to reconcile a promotion whose outcome was interrupted, not to repeat it blindly.",
        parameters: %{
          type: "object",
          properties: %{hash: hash},
          additionalProperties: false
        },
        call: fn args, _ ->
          operation = if Map.has_key?(args, "hash"), do: :release, else: :releases
          request(run, operation, args)
        end,
        replay_safe: true,
        read_only: true
      ),
      Condukt.tool(
        name: "merge_behavior_release",
        description:
          "Merge an exact independently human-approved proposal into ops/main when the person requests a merge. Requires the triggering author's merge grant and unchanged reviewed main base; does not activate behavior. A main conflict requires a new proposal and review. If interrupted, inspect_behavior_releases first: merging means outcome unknown, merged means awaiting explicit activation. A deliberate retry reconciles only this exact commit; never substitute another release.",
        parameters: %{
          type: "object",
          properties: %{hash: hash},
          required: ["hash"],
          additionalProperties: false
        },
        call: fn args, _ -> request(run, :merge, args) end
      ),
      Condukt.tool(
        name: "promote_behavior_release",
        description:
          "Activate one exact release already merged into ops/main, only when the person requests activation. Requires the triggering author's activate grant; rechecks main membership, baseline, runtime, compatibility and the reviewer's current owner grants. Does not approve, merge, grant permissions or execute methods. If interrupted, inspect_behavior_releases to determine the result before acting again.",
        parameters: %{
          type: "object",
          properties: %{hash: hash},
          required: ["hash"],
          additionalProperties: false
        },
        call: fn args, _ -> request(run, :activate, args) end
      )
    ]
  end

  defp request(run, operation, args) do
    case Threads.with_attempt(run, fn _thread, fresh ->
           Records.author(fresh, &Behaviors.for_scope(&1, operation, args))
         end) do
      {:ok, result} -> result
      error -> error
    end
  end
end

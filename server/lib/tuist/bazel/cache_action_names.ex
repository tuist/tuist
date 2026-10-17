defmodule Tuist.Bazel.CacheActionNames do
  @moduledoc "Optional profile descriptions for cache actions, without changing cache identity."

  import Ecto.Query

  alias Tuist.Bazel.Profile
  alias Tuist.Bazel.ProfileSteps
  alias Tuist.ReapiCache.CacheEvent

  def query(events, project_id, invocation_id) do
    fields = CacheEvent.__schema__(:fields)
    version = Profile.steps_version(%{project_id: project_id, invocation_id: invocation_id})

    events =
      if is_binary(version) and version != "" do
        names = names(events, project_id, invocation_id, version)

        from(e in events,
          left_join: n in subquery(names),
          on:
            e.operation == "action_cache" and e.action_digest == n.action_digest and
              e.action_mnemonic == n.action_mnemonic and e.target_label == n.target_label and
              e.configuration_id == n.configuration_id,
          select: map(e, ^fields),
          select_merge: %{
            action_display_name: fragment("coalesce(nullIf(?, ''), ?)", n.display_name, e.action_mnemonic)
          }
        )
      else
        from(e in events,
          select: map(e, ^fields),
          select_merge: %{action_display_name: e.action_mnemonic}
        )
      end

    searchable =
      from(e in subquery(events),
        select: e,
        select_merge: %{
          action_search: fragment("concat(?, ' ', ?, ' ', ?)", e.action_display_name, e.action_mnemonic, e.target_label)
        }
      )

    from(e in subquery(searchable))
  end

  defp names(events, project_id, invocation_id, version) do
    # Resolve a miss through the hit/write for the same action digest. Conflicting
    # output hints or profile descriptions never select an arbitrary name.
    outputs =
      from(e in events,
        where: e.operation == "action_cache" and e.output_path != "",
        group_by: [e.action_digest, e.action_mnemonic, e.target_label, e.configuration_id],
        select: %{
          action_digest: e.action_digest,
          action_mnemonic: e.action_mnemonic,
          target_label: e.target_label,
          configuration_id: e.configuration_id,
          output_path: fragment("if(uniqExact(?) = 1, any(?), '')", e.output_path, e.output_path)
        }
      )

    descriptions =
      from(s in ProfileSteps,
        hints: ["FINAL"],
        where: s.project_id == ^project_id and s.invocation_id == ^invocation_id,
        where: s.version == ^version,
        where: s.primary_output != "" and s.target != "" and s.category != "" and s.title != "",
        group_by: [s.primary_output, s.target, s.category],
        select: %{
          output_path: s.primary_output,
          target_label: s.target,
          action_mnemonic: s.category,
          display_name: fragment("if(uniqExact(?) = 1, any(?), '')", s.title, s.title)
        }
      )

    from(o in subquery(outputs),
      left_join: d in subquery(descriptions),
      on:
        o.output_path != "" and o.output_path == d.output_path and
          o.target_label == d.target_label and o.action_mnemonic == d.action_mnemonic,
      select: %{
        action_digest: o.action_digest,
        action_mnemonic: o.action_mnemonic,
        target_label: o.target_label,
        configuration_id: o.configuration_id,
        display_name: d.display_name
      }
    )
  end
end

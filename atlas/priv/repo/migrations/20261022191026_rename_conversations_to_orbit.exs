defmodule Atlas.Repo.Migrations.RenameConversationsToOrbit do
  use Ecto.Migration

  @tables [
    conversations: :orbit_threads,
    conversation_participants: :orbit_participants,
    conversation_runs: :orbit_runs,
    conversation_messages: :orbit_messages,
    conversation_viewers: :orbit_viewers
  ]

  def up do
    for {old, new} <- @tables do
      rename table(old), to: table(new)
    end

    for {_old, new} <- tl(@tables) do
      rename table(new), :conversation_id, to: :thread_id
    end

    rename table(:inference_model_bindings), :atlas_conversations, to: :atlas_orbit
    flush()

    for {_old, new} <- @tables, do: rename_objects(new, :up)

    execute("""
    ALTER INDEX inference_model_bindings_single_atlas_conversations_index
    RENAME TO inference_model_bindings_single_atlas_orbit_index
    """)

    rename_execution(
      "conversations",
      "orbit",
      "Atlas.Conversations",
      "Atlas.Orbit",
      "RunConversation",
      "RunThread"
    )
  end

  def down do
    rename_execution(
      "orbit",
      "conversations",
      "Atlas.Orbit",
      "Atlas.Conversations",
      "RunThread",
      "RunConversation"
    )

    execute("""
    ALTER INDEX inference_model_bindings_single_atlas_orbit_index
    RENAME TO inference_model_bindings_single_atlas_conversations_index
    """)

    for {_old, new} <- @tables, do: rename_objects(new, :down)

    rename table(:inference_model_bindings), :atlas_orbit, to: :atlas_conversations

    for {_old, new} <- tl(@tables) do
      rename table(new), :thread_id, to: :conversation_id
    end

    for {old, new} <- Enum.reverse(@tables) do
      rename table(new), to: table(old)
    end
  end

  # Table/column renames preserve references but PostgreSQL keeps their old
  # constraint/index names. Keep changeset constraint matching correct too.
  defp rename_objects(table, direction) do
    expression =
      case direction do
        :up ->
          "replace(replace(replace(object_name, 'conversation_id', 'thread_id'), 'conversations', 'orbit_threads'), 'conversation_', 'orbit_')"

        :down ->
          "replace(replace(replace(object_name, 'thread_id', 'conversation_id'), 'orbit_threads', 'conversations'), 'orbit_', 'conversation_')"
      end

    execute("""
    DO $$
    DECLARE object_name text; new_name text;
    BEGIN
      FOR object_name IN SELECT conname FROM pg_constraint WHERE conrelid = '#{table}'::regclass LOOP
        new_name := #{expression};
        IF new_name <> object_name THEN
          EXECUTE format('ALTER TABLE %I RENAME CONSTRAINT %I TO %I', '#{table}', object_name, new_name);
        END IF;
      END LOOP;
      FOR object_name IN SELECT indexname FROM pg_indexes WHERE schemaname = current_schema() AND tablename = '#{table}' LOOP
        new_name := #{expression};
        IF new_name <> object_name THEN
          EXECUTE format('ALTER INDEX %I RENAME TO %I', object_name, new_name);
        END IF;
      END LOOP;
    END $$
    """)
  end

  # Preserve token hashes, job arguments/run IDs, session IDs, encrypted
  # checkpoints and tool results. Drain the old workers before this migration;
  # old/new server binaries cannot share the renamed tables during rollout.
  defp rename_execution(old_role, new_role, old_module, new_module, old_worker, new_worker) do
    {old_label, new_label} =
      if new_role == "orbit",
        do: {"conversation_run:", "orbit_run:"},
        else: {"orbit_run:", "conversation_run:"}

    execute(
      "UPDATE inference_tokens SET atlas_role = '#{new_role}' WHERE atlas_role = '#{old_role}'"
    )

    execute("""
    UPDATE oban_jobs
    SET worker = '#{new_module}.Workers.#{new_worker}', queue = '#{new_role}'
    WHERE worker = '#{old_module}.Workers.#{old_worker}'
    """)

    execute("""
    UPDATE agent_sessions
    SET agent = '#{new_module}.Agent', prompt = replace(prompt, '#{old_label}', '#{new_label}')
    WHERE agent = '#{old_module}.Agent'
    """)
  end
end

defmodule Tuist.BuildEntities.Resources do
  @moduledoc false

  alias Tuist.BuildEntities

  @resources [
    %{
      key: :bazel_actions,
      system: :bazel,
      kind: "action",
      singular: :action,
      plural: :actions,
      id_param: :action_id,
      history_key: :executions,
      title: "BazelBuildAction",
      label: "Bazel actions",
      label_singular: "a Bazel action",
      api_path: "/bazel/actions",
      history_path: "executions",
      path: "/builds/bazel/actions"
    },
    %{
      key: :gradle_tasks,
      system: :gradle,
      kind: "task",
      singular: :task,
      plural: :tasks,
      id_param: :task_id,
      history_key: :executions,
      title: "GradleTask",
      label: "Gradle tasks",
      label_singular: "a Gradle task",
      api_path: "/gradle/tasks",
      history_path: "executions",
      path: "/builds/gradle/tasks"
    },
    %{
      key: :xcode_modules,
      system: :xcode,
      kind: "module",
      singular: :module,
      plural: :modules,
      id_param: :module_id,
      history_key: :cache_events,
      title: "XcodeCachedModule",
      label: "Xcode modules",
      label_singular: "an Xcode module",
      api_path: "/xcode/modules",
      history_path: "events",
      path: "/builds/xcode/modules"
    },
    %{
      key: :once_actions,
      system: :once,
      kind: "action",
      singular: :action,
      plural: :actions,
      id_param: :action_id,
      history_key: :executions,
      title: "OnceAction",
      label: "Once actions",
      label_singular: "a Once action",
      api_path: "/once/actions",
      history_path: "executions",
      path: "/builds/once/actions"
    },
    %{
      key: :mix_files,
      system: :mix,
      kind: "file",
      singular: :file,
      plural: :files,
      id_param: :file_id,
      history_key: :compilations,
      title: "MixCompiledFile",
      label: "Mix compiled files",
      label_singular: "a Mix compiled file",
      api_path: "/mix/files",
      history_path: "compilations",
      path: "/builds/mix/files"
    },
    %{
      key: :mix_modules,
      system: :mix,
      kind: "module",
      singular: :module,
      plural: :modules,
      id_param: :module_id,
      history_key: :compilations,
      title: "MixCompiledModule",
      label: "Mix compiled modules",
      label_singular: "a Mix compiled module",
      api_path: "/mix/modules",
      history_path: "compilations",
      path: "/builds/mix/modules"
    }
  ]

  def all, do: @resources
  def fetch!(key), do: Enum.find(@resources, &(&1.key == key)) || raise(ArgumentError, "Unknown resource")

  def for_project(project) do
    if BuildEntities.enabled?(project),
      do: Enum.filter(@resources, &(&1.system == project.build_system)),
      else: []
  end
end

defmodule Tuist.BuildEntities.Resources do
  @moduledoc false

  @resources [
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
      key: :xcode_cache_actions,
      system: :xcode,
      kind: "cache_action",
      singular: :cache_action,
      plural: :cache_actions,
      id_param: :cache_action_id,
      history_key: :cache_events,
      title: "XcodeCacheAction",
      label: "Xcode cache actions",
      label_singular: "an Xcode cache action",
      api_path: "/xcode/cache-actions",
      history_path: "events",
      path: "/xcode-cache/actions"
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
      label: "Xcode generated-project modules",
      label_singular: "an Xcode generated-project module",
      api_path: "/xcode/modules",
      history_path: "events",
      path: "/builds/xcode/modules"
    },
    %{
      key: :bazel_cache_actions,
      system: :bazel,
      kind: "cache_action",
      singular: :cache_action,
      plural: :cache_actions,
      id_param: :cache_action_id,
      history_key: :cache_events,
      title: "BazelCacheAction",
      label: "Bazel cache actions",
      label_singular: "a Bazel cache action",
      api_path: "/bazel/cache-actions",
      history_path: "events",
      path: "/builds/bazel/cache-actions"
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
  def for_project(project), do: Enum.filter(@resources, &(&1.system == project.build_system))
end

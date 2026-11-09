defmodule Pulse.Test.Case do
  @moduledoc "Test-owned dependency context and isolated service instances."
  use ExUnit.CaseTemplate

  import ExUnit.Callbacks,
    except: [start_supervised: 1, start_supervised: 2, start_supervised!: 1, start_supervised!: 2]

  alias Pulse.Loki.Tail
  alias Pulse.PromQL.QuerySlots
  alias Pulse.PromQL.TaskSupervisor
  alias Pulse.Storage.Memory

  using do
    quote do
      import ExUnit.Callbacks,
        except: [start_supervised: 1, start_supervised: 2, start_supervised!: 1, start_supervised!: 2]

      import Pulse.Test.Case,
        only: [start_supervised: 1, start_supervised: 2, start_supervised!: 1, start_supervised!: 2]
    end
  end

  setup tags do
    setup_runtime(tags)
  end

  def setup_runtime(%{module: module}) do
    runtime =
      Pulse.Runtime.new(
        instance: module,
        configs: Map.new(Application.get_all_env(:pulse), fn {key, value} -> {{:pulse, key}, value} end)
      )

    Pulse.Runtime.install(runtime)
    start_supervised!(Memory)
    start_supervised!(Pulse.Metrics)
    start_supervised!(Pulse.SelfMetrics)
    start_supervised!({Task.Supervisor, name: TaskSupervisor, max_children: 4})
    start_supervised!({Registry, keys: :unique, name: QuerySlots})
    start_supervised!(Tail)
    {:ok, runtime: runtime}
  end

  def start_supervised(child, opts \\ []), do: ExUnit.Callbacks.start_supervised(Pulse.Runtime.child_spec(child), opts)

  def start_supervised!(child, opts \\ []),
    do: ExUnit.Callbacks.start_supervised!(Pulse.Runtime.child_spec(child), opts)
end

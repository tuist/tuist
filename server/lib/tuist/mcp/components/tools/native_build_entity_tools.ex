defmodule Tuist.MCP.Components.Tools.ListGradleTasks do
  @moduledoc false
  use Tuist.MCP.Components.Tools.BuildEntityTool, resource: :gradle_tasks, action: :index
end

defmodule Tuist.MCP.Components.Tools.GetGradleTask do
  @moduledoc false
  use Tuist.MCP.Components.Tools.BuildEntityTool, resource: :gradle_tasks, action: :show
end

defmodule Tuist.MCP.Components.Tools.ListGradleTaskExecutions do
  @moduledoc false
  use Tuist.MCP.Components.Tools.BuildEntityTool, resource: :gradle_tasks, action: :history
end

defmodule Tuist.MCP.Components.Tools.ListXcodeCacheActions do
  @moduledoc false
  use Tuist.MCP.Components.Tools.BuildEntityTool, resource: :xcode_cache_actions, action: :index
end

defmodule Tuist.MCP.Components.Tools.GetXcodeCacheAction do
  @moduledoc false
  use Tuist.MCP.Components.Tools.BuildEntityTool, resource: :xcode_cache_actions, action: :show
end

defmodule Tuist.MCP.Components.Tools.ListXcodeCacheActionEvents do
  @moduledoc false
  use Tuist.MCP.Components.Tools.BuildEntityTool, resource: :xcode_cache_actions, action: :history
end

defmodule Tuist.MCP.Components.Tools.ListXcodeModules do
  @moduledoc false
  use Tuist.MCP.Components.Tools.BuildEntityTool, resource: :xcode_modules, action: :index
end

defmodule Tuist.MCP.Components.Tools.GetXcodeModule do
  @moduledoc false
  use Tuist.MCP.Components.Tools.BuildEntityTool, resource: :xcode_modules, action: :show
end

defmodule Tuist.MCP.Components.Tools.ListXcodeModuleCacheEvents do
  @moduledoc false
  use Tuist.MCP.Components.Tools.BuildEntityTool, resource: :xcode_modules, action: :history
end

defmodule Tuist.MCP.Components.Tools.ListBazelCacheActions do
  @moduledoc false
  use Tuist.MCP.Components.Tools.BuildEntityTool, resource: :bazel_cache_actions, action: :index
end

defmodule Tuist.MCP.Components.Tools.GetBazelCacheAction do
  @moduledoc false
  use Tuist.MCP.Components.Tools.BuildEntityTool, resource: :bazel_cache_actions, action: :show
end

defmodule Tuist.MCP.Components.Tools.ListBazelCacheActionEvents do
  @moduledoc false
  use Tuist.MCP.Components.Tools.BuildEntityTool, resource: :bazel_cache_actions, action: :history
end

defmodule Tuist.MCP.Components.Tools.ListOnceActions do
  @moduledoc false
  use Tuist.MCP.Components.Tools.BuildEntityTool, resource: :once_actions, action: :index
end

defmodule Tuist.MCP.Components.Tools.GetOnceAction do
  @moduledoc false
  use Tuist.MCP.Components.Tools.BuildEntityTool, resource: :once_actions, action: :show
end

defmodule Tuist.MCP.Components.Tools.ListOnceActionExecutions do
  @moduledoc false
  use Tuist.MCP.Components.Tools.BuildEntityTool, resource: :once_actions, action: :history
end

defmodule Tuist.MCP.Components.Tools.ListMixFiles do
  @moduledoc false
  use Tuist.MCP.Components.Tools.BuildEntityTool, resource: :mix_files, action: :index
end

defmodule Tuist.MCP.Components.Tools.GetMixFile do
  @moduledoc false
  use Tuist.MCP.Components.Tools.BuildEntityTool, resource: :mix_files, action: :show
end

defmodule Tuist.MCP.Components.Tools.ListMixFileCompilations do
  @moduledoc false
  use Tuist.MCP.Components.Tools.BuildEntityTool, resource: :mix_files, action: :history
end

defmodule Tuist.MCP.Components.Tools.ListMixModules do
  @moduledoc false
  use Tuist.MCP.Components.Tools.BuildEntityTool, resource: :mix_modules, action: :index
end

defmodule Tuist.MCP.Components.Tools.GetMixModule do
  @moduledoc false
  use Tuist.MCP.Components.Tools.BuildEntityTool, resource: :mix_modules, action: :show
end

defmodule Tuist.MCP.Components.Tools.ListMixModuleCompilations do
  @moduledoc false
  use Tuist.MCP.Components.Tools.BuildEntityTool, resource: :mix_modules, action: :history
end

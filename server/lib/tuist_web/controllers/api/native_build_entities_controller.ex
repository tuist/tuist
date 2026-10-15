defmodule TuistWeb.API.GradleTaskDetailsController do
  @moduledoc false
  use TuistWeb.API.BuildEntityController, resource: :gradle_tasks
end

defmodule TuistWeb.API.XcodeCacheActionsController do
  @moduledoc false
  use TuistWeb.API.BuildEntityController, resource: :xcode_cache_actions
end

defmodule TuistWeb.API.XcodeModulesController do
  @moduledoc false
  use TuistWeb.API.BuildEntityController, resource: :xcode_modules
end

defmodule TuistWeb.API.BazelCacheActionsController do
  @moduledoc false
  use TuistWeb.API.BuildEntityController, resource: :bazel_cache_actions
end

defmodule TuistWeb.API.OnceActionsController do
  @moduledoc false
  use TuistWeb.API.BuildEntityController, resource: :once_actions
end

defmodule TuistWeb.API.MixFilesController do
  @moduledoc false
  use TuistWeb.API.BuildEntityController, resource: :mix_files
end

defmodule TuistWeb.API.MixModulesController do
  @moduledoc false
  use TuistWeb.API.BuildEntityController, resource: :mix_modules
end

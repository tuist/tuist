defmodule Atlas.Policy do
  use LetMe.Policy,
    check_module: Atlas.Policy.Checks,
    error: :unauthorized

  object :instance do
    action :read do
      allow(:authenticated)
    end

    action :write do
      allow(:authenticated)
    end
  end

  object :integration do
    action :read do
      allow(:authenticated)
    end

    action :write do
      allow(:authenticated)
    end
  end
end

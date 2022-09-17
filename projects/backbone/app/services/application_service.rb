# frozen_string_literal: true

class ApplicationService
  class << self
    def call(*args, &block)
      new(*args).call(&block)
    end
  end

  def call
    raise NotImplementedError
  end
end

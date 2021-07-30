# frozen_string_literal: true

class ApplicationService
  def self.call(*args, &block)
    new(*args).call(&block)
  end

  def call
    raise NotImplementedError
  end
end

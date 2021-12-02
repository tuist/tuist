# frozen_string_literal: true

module CocoaPodsInteractor
  module Utilities
    class Errors
      Error = Class.new(StandardError)
      AbortError = Class.new(Error)
      AbortSilentError = Class.new(Error)
      BugError = Class.new(Error)
      BugSilentError = Class.new(Error)
    end
  end
end

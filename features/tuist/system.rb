require "open3"

module Tuist
  module System

    SystemError = Class.new(StandardError)

    def self.run(*args)
      _, err, status = Open3.capture3(*args)
      raise SystemError, err unless status.success?
    end

    def self.xcodebuild(*args)
      self.run("xcodebuild", *args)
    end

  end
end

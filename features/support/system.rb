# frozen_string_literal: true

require "open3"

module System
  def system(*args)
    _, err, status = Open3.capture3(*args)
    assert(status.success?, err)
  end

  def xcodebuild(*args)
    system("xcodebuild", *args)
  end
end

World(System)

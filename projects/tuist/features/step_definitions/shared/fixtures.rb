# frozen_string_literal: true

require "fileutils"

Then(/I copy the fixture (.+) into the working directory/) do |fixture|
  fixtures_path = File.expand_path("../../../fixtures", __dir__)
  fixture_path = File.join(fixtures_path, fixture)
  assert(false, "Fixture #{fixture} not found") unless File.exist?(fixture_path)

  FileUtils.cp_r(File.join(fixture_path, "."), @dir)
end

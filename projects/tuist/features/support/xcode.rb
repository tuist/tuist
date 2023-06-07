# frozen_string_literal: true

require "minitest/assertions"
require "xcodeproj"
require "simctl"

module Xcode
  include Minitest::Assertions

  class << self
    def workspace(workspace_path)
      Xcodeproj::Workspace.new_from_xcworkspace(workspace_path)
    end

    def projects(workspace_path)
      workspace(workspace_path)
        .file_references
        .filter { |f| f.path.include?(".xcodeproj") }
        .map { |f| File.join(File.dirname(workspace_path), f.path) }
        .map { |p| Xcodeproj::Project.open(p) }
    end

    def product_with_name(name, destination:, derived_data_path:)
      glob = File.join(derived_data_path, "**/Build/**/Products/#{destination}/#{name}/")
      Dir.glob(glob).max_by { |f| File.mtime(f) }
    end

    def find_framework(product:, destination:, framework:, derived_data_path:)
      product_path = product_with_name(
        product,
        destination: destination,
        derived_data_path: derived_data_path
      )

      return if product_path.nil?

      framework_glob = File.join(product_path, "**/Frameworks/#{framework}.framework")
      # /path/to/product/Frameworks/MyFramework.framework
      framework_path = Dir.glob(framework_glob).first

      framework_path
    end

    def find_app_clip(product:, destination:, app_clip:, derived_data_path:)
      product_path = product_with_name(
        product,
        destination: destination,
        derived_data_path: derived_data_path
      )

      return if product_path.nil?

      app_clip_glob = File.join(product_path, "/AppClips/#{app_clip}.app")
      # /path/to/product/AppClips/AppClip.app
      app_clip_path = Dir.glob(app_clip_glob).first

      app_clip_path
    end

    def find_resource(product:, destination:, resource:, derived_data_path:)
      product_path = product_with_name(
        product,
        destination: destination,
        derived_data_path: derived_data_path
      )
      return if product_path.nil?

      resource_glob = File.join(product_path, "**/#{resource}")
      # /path/to/product/resource.png
      Dir.glob(resource_glob).first
    end

    def find_extension(product:, destination:, extension:, derived_data_path:)
      product_path = product_with_name(
        product,
        destination: destination,
        derived_data_path: derived_data_path
      )

      return if product_path.nil?

      extension_glob = File.join(product_path, "Plugins/#{extension}.appex")
      # /path/to/product/Plugins/MyExtension.appex
      extension_path = Dir.glob(extension_glob).first

      extension_path
    end

    def find_extensionKitExtension(product:, destination:, extension:, derived_data_path:)
      product_path = product_with_name(
        product,
        destination: destination,
        derived_data_path: derived_data_path
      )

      return if product_path.nil?

      extension_glob = File.join(product_path, "Extensions/#{extension}.appex")
      # /path/to/product/Extensions/MyExtension.appex
      extension_path = Dir.glob(extension_glob).first

      extension_path
    end

    def find_headers(product:, destination:, derived_data_path:)
      product_path = product_with_name(
        product,
        destination: destination,
        derived_data_path: derived_data_path
      )
      return if product_path.nil?

      headers_glob = File.join(product_path, "**/*.h")
      # /path/to/product/header.h
      Dir.glob(headers_glob)
    end

    def valid_simulator_destination_for_platform(platform)
      # watchOS simulators are bundled with iOS simulators
      platform = "iOS" if platform == "watchOS"
      device = SimCtl
        .list_devices
        .select { |d| d.is_available && d.runtime.name.downcase.include?(platform.downcase) }
        .sort { |l, r| l.runtime.version <=> r.runtime.version }
        .last

      return nil if device.nil?

      "platform=#{platform} Simulator,id=#{device.udid}"
    end
  end
end

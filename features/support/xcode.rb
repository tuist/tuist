# frozen_string_literal: true

module Xcode
  include MiniTest::Assertions

  def self.product_with_name(name, destination:, derived_data_path:)
    glob = File.join(derived_data_path, "**/Build/**/Products/#{destination}/#{name}/")
    Dir.glob(glob).max_by { |f| File.mtime(f) }
  end

  def self.find_framework(product:, destination:, framework:, derived_data_path:)
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

  def self.find_resource(product:, destination:, resource:, derived_data_path:)
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
end

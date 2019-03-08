# frozen_string_literal: true

Then("the product {string} with destination {string} contains the framework {string} with architecture {string}") do |product, destination, framework, architecture|
  framework_path = Xcode.find_framework(
    product: product,
    destination: destination,
    framework: framework,
    derived_data_path: @derived_data_path
  )
  binary_path = File.join(framework_path, framework)
  out, err, status = Open3.capture3("file", binary_path)
  assert(status.success?, err)
  assert(out.include?(architecture))
end

Then("the product {string} with destination {string} contains the framework {string} without architecture {string}") do |product, destination, framework, architecture|
  framework_path = Xcode.find_framework(
    product: product,
    destination: destination,
    framework: framework,
    derived_data_path: @derived_data_path
  )
  binary_path = File.join(framework_path, framework)
  out, err, status = Open3.capture3("file", binary_path)
  assert(status.success?, err)
  refute(out.include?(architecture))
end

Then("the product {string} with destination {string} contains resource {string}") do |product, destination, resource|
  resource_path = Xcode.find_resource(
    product: product,
    destination: destination,
    resource: resource,
    derived_data_path: @derived_data_path
  )

  assert(resource_path.nil? == false)
end

Then("the product {string} with destination {string} does not contain resource {string}") do |product, destination, resource|
  resource_path = Xcode.find_resource(
    product: product,
    destination: destination,
    resource: resource,
    derived_data_path: @derived_data_path
  )

  assert(resource_path.nil? == true)
end

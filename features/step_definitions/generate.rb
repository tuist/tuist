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

                                        assert(resource_path)
end

Then("the product {string} with destination {string} does not contain resource {string}") do |product, destination, resource|
    resource_path = Xcode.find_resource(
                                        product: product,
                                        destination: destination,
                                        resource: resource,
                                        derived_data_path: @derived_data_path
                                        )
                                        refute(resource_path)
end

Then("the product {string} with destination {string} has an entry of {string} in the info.plist with the value of {string}") do |product, destination, setting, value|
    plist_path = Xcode.info_plist_for_product_with_name(
                               product: product,
                               destination: destination,
                               derived_data_path: @derived_data_path
                               )
   plist = CFPropertyList::List.new(:file => plist_path)
   data = CFPropertyList.native_types(plist.value)
   assert_equal(data[setting], value, "Could not find `#{setting}` with the value of `#{value}`")
end

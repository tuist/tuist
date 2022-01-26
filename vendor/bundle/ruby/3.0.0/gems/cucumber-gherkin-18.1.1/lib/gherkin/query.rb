module Gherkin
  class Query
    def initialize
      @ast_node_locations = {}
    end

    def update(message)
      update_feature(message.gherkin_document.feature) if message.gherkin_document
    end

    def location(ast_node_id)
      return @ast_node_locations[ast_node_id] if @ast_node_locations.has_key?(ast_node_id)
      raise AstNodeNotLocatedException, "No location found for #{ast_node_id} }. Known: #{@ast_node_locations.keys}"
    end

    private

    def update_feature(feature)
      return if feature.nil?
      store_nodes_location(feature.tags)

      feature.children.each do |child|
        update_rule(child.rule) if child.rule
        update_background(child.background) if child.background
        update_scenario(child.scenario) if child.scenario
      end
    end

    def update_rule(rule)
      rule.children.each do |child|
        update_background(child.background) if child.background
        update_scenario(child.scenario) if child.scenario
      end
    end

    def update_background(background)
      update_steps(background.steps)
    end

    def update_scenario(scenario)
      store_node_location(scenario)
      store_nodes_location(scenario.tags)
      update_steps(scenario.steps)
      scenario.examples.each do |examples|
        store_nodes_location(examples.tags)
        store_nodes_location(examples.table_body)
      end
    end

    def update_steps(steps)
      store_nodes_location(steps)
    end

    def store_nodes_location(nodes)
      nodes.each { |node| store_node_location(node) }
    end

    def store_node_location(node)
      @ast_node_locations[node.id] = node.location
    end
  end
end

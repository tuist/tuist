require 'cucumber/cucumber_expressions/group'

module Cucumber
  module CucumberExpressions
    class GroupBuilder
      attr_accessor :source

      def initialize
        @group_builders = []
        @capturing = true
      end

      def add(group_builder)
        @group_builders.push(group_builder)
      end

      def build(match, group_indices)
        group_index = group_indices.next
        children = @group_builders.map {|gb| gb.build(match, group_indices)}
        Group.new(match[group_index], match.offset(group_index)[0], match.offset(group_index)[1], children)
      end

      def set_non_capturing!
        @capturing = false
      end

      def capturing?
        @capturing
      end

      def move_children_to(group_builder)
        @group_builders.each do |child|
          group_builder.add(child)
        end
      end

      def children
        @group_builders
      end
    end
  end
end

require 'naturally/segment'

# A module which performs natural sorting on a variety of number
# formats. (See the specs for examples.)
module Naturally
  # Perform a natural sort. Supports two syntaxes:
  #
  # 1. sort(objects)  # Simple arrays
  # 2. sort(objects, by: some_attribute)  # Complex objects
  #
  # @param [Array<String>] an_array the list of numbers to sort.
  # @param [by] (optional) an attribute of the array by which to sort.
  # @return [Array<String>] the numbers sorted naturally.
  def self.sort(an_array, by:nil)
    if by.nil?
      an_array.sort_by { |x| normalize(x) }
    else
      self.sort_by(an_array, by)
    end
  end

  # Sort an array of objects "naturally" by a given attribute.
  # If block is given, attribute is ignored and each object
  # is yielded to the block to obtain the sort key.
  #
  # @param [Array<Object>] an_array the list of objects to sort.
  # @param [Symbol] an_attribute the attribute by which to sort.
  # @param [Block] &block a block that should evaluate to the
  #        sort key for the yielded object
  # @return [Array<Object>] the objects in natural sort order.
  def self.sort_by(an_array, an_attribute=nil, &block)
    return sort_by_block(an_array, &block) if block_given?
    an_array.sort_by { |obj| normalize(obj.send(an_attribute)) }
  end

  # Convert the given number to an array of {Segment}s.
  # This enables it to be sorted against other arrays
  # by the built-in #sort method.
  #
  # For example, '1.2a.3' becomes
  # [Segment<'1'>, Segment<'2a'>, Segment<'3'>]
  #
  # @param [String] complex_number the number in a hierarchical form
  #                 such as 1.2a.3.
  # @return [Array<Segment>] an array of Segments which
  #         can be sorted naturally via a standard #sort.
  def self.normalize(complex_number)
    tokens = complex_number.to_s.gsub(/\_/,'').scan(/\p{Word}+/)
    tokens.map { |t| Segment.new(t) }
  end

  private
  # Sort an array of objects "naturally", yielding each object
  # to the block to obtain the sort key.
  #
  # @param [Array<Object>] an_array the list of objects to sort.
  # @param [Block] &block a block that should evaluate to the
  #        sort key for the yielded object
  # @return [Array<Object>] the objects in natural sort order.
  def self.sort_by_block(an_array, &block)
    an_array.sort_by { |obj| normalize(yield(obj)) }
  end
end

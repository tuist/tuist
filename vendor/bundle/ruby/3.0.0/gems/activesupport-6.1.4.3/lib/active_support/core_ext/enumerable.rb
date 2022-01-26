# frozen_string_literal: true

module Enumerable
  INDEX_WITH_DEFAULT = Object.new
  private_constant :INDEX_WITH_DEFAULT

  # Enumerable#sum was added in Ruby 2.4, but it only works with Numeric elements
  # when we omit an identity.

  # :stopdoc:

  # We can't use Refinements here because Refinements with Module which will be prepended
  # doesn't work well https://bugs.ruby-lang.org/issues/13446
  alias :_original_sum_with_required_identity :sum
  private :_original_sum_with_required_identity

  # :startdoc:

  # Calculates a sum from the elements.
  #
  #  payments.sum { |p| p.price * p.tax_rate }
  #  payments.sum(&:price)
  #
  # The latter is a shortcut for:
  #
  #  payments.inject(0) { |sum, p| sum + p.price }
  #
  # It can also calculate the sum without the use of a block.
  #
  #  [5, 15, 10].sum # => 30
  #  ['foo', 'bar'].sum # => "foobar"
  #  [[1, 2], [3, 1, 5]].sum # => [1, 2, 3, 1, 5]
  #
  # The default sum of an empty list is zero. You can override this default:
  #
  #  [].sum(Payment.new(0)) { |i| i.amount } # => Payment.new(0)
  def sum(identity = nil, &block)
    if identity
      _original_sum_with_required_identity(identity, &block)
    elsif block_given?
      map(&block).sum(identity)
    else
      inject(:+) || 0
    end
  end

  # Convert an enumerable to a hash, using the block result as the key and the
  # element as the value.
  #
  #   people.index_by(&:login)
  #   # => { "nextangle" => <Person ...>, "chade-" => <Person ...>, ...}
  #
  #   people.index_by { |person| "#{person.first_name} #{person.last_name}" }
  #   # => { "Chade- Fowlersburg-e" => <Person ...>, "David Heinemeier Hansson" => <Person ...>, ...}
  def index_by
    if block_given?
      result = {}
      each { |elem| result[yield(elem)] = elem }
      result
    else
      to_enum(:index_by) { size if respond_to?(:size) }
    end
  end

  # Convert an enumerable to a hash, using the element as the key and the block
  # result as the value.
  #
  #   post = Post.new(title: "hey there", body: "what's up?")
  #
  #   %i( title body ).index_with { |attr_name| post.public_send(attr_name) }
  #   # => { title: "hey there", body: "what's up?" }
  #
  # If an argument is passed instead of a block, it will be used as the value
  # for all elements:
  #
  #   %i( created_at updated_at ).index_with(Time.now)
  #   # => { created_at: 2020-03-09 22:31:47, updated_at: 2020-03-09 22:31:47 }
  def index_with(default = INDEX_WITH_DEFAULT)
    if block_given?
      result = {}
      each { |elem| result[elem] = yield(elem) }
      result
    elsif default != INDEX_WITH_DEFAULT
      result = {}
      each { |elem| result[elem] = default }
      result
    else
      to_enum(:index_with) { size if respond_to?(:size) }
    end
  end

  # Returns +true+ if the enumerable has more than 1 element. Functionally
  # equivalent to <tt>enum.to_a.size > 1</tt>. Can be called with a block too,
  # much like any?, so <tt>people.many? { |p| p.age > 26 }</tt> returns +true+
  # if more than one person is over 26.
  def many?
    cnt = 0
    if block_given?
      any? do |element|
        cnt += 1 if yield element
        cnt > 1
      end
    else
      any? { (cnt += 1) > 1 }
    end
  end

  # Returns a new array that includes the passed elements.
  #
  #   [ 1, 2, 3 ].including(4, 5)
  #   # => [ 1, 2, 3, 4, 5 ]
  #
  #   ["David", "Rafael"].including %w[ Aaron Todd ]
  #   # => ["David", "Rafael", "Aaron", "Todd"]
  def including(*elements)
    to_a.including(*elements)
  end

  # The negative of the <tt>Enumerable#include?</tt>. Returns +true+ if the
  # collection does not include the object.
  def exclude?(object)
    !include?(object)
  end

  # Returns a copy of the enumerable excluding the specified elements.
  #
  #   ["David", "Rafael", "Aaron", "Todd"].excluding "Aaron", "Todd"
  #   # => ["David", "Rafael"]
  #
  #   ["David", "Rafael", "Aaron", "Todd"].excluding %w[ Aaron Todd ]
  #   # => ["David", "Rafael"]
  #
  #   {foo: 1, bar: 2, baz: 3}.excluding :bar
  #   # => {foo: 1, baz: 3}
  def excluding(*elements)
    elements.flatten!(1)
    reject { |element| elements.include?(element) }
  end

  # Alias for #excluding.
  def without(*elements)
    excluding(*elements)
  end

  # Extract the given key from each element in the enumerable.
  #
  #   [{ name: "David" }, { name: "Rafael" }, { name: "Aaron" }].pluck(:name)
  #   # => ["David", "Rafael", "Aaron"]
  #
  #   [{ id: 1, name: "David" }, { id: 2, name: "Rafael" }].pluck(:id, :name)
  #   # => [[1, "David"], [2, "Rafael"]]
  def pluck(*keys)
    if keys.many?
      map { |element| keys.map { |key| element[key] } }
    else
      key = keys.first
      map { |element| element[key] }
    end
  end

  # Extract the given key from the first element in the enumerable.
  #
  #   [{ name: "David" }, { name: "Rafael" }, { name: "Aaron" }].pick(:name)
  #   # => "David"
  #
  #   [{ id: 1, name: "David" }, { id: 2, name: "Rafael" }].pick(:id, :name)
  #   # => [1, "David"]
  def pick(*keys)
    return if none?

    if keys.many?
      keys.map { |key| first[key] }
    else
      first[keys.first]
    end
  end

  # Returns a new +Array+ without the blank items.
  # Uses Object#blank? for determining if an item is blank.
  #
  #    [1, "", nil, 2, " ", [], {}, false, true].compact_blank
  #    # =>  [1, 2, true]
  #
  #    Set.new([nil, "", 1, 2])
  #    # => [2, 1] (or [1, 2])
  #
  # When called on a +Hash+, returns a new +Hash+ without the blank values.
  #
  #    { a: "", b: 1, c: nil, d: [], e: false, f: true }.compact_blank
  #    #=> { b: 1, f: true }
  def compact_blank
    reject(&:blank?)
  end
end

class Hash
  # Hash#reject has its own definition, so this needs one too.
  def compact_blank #:nodoc:
    reject { |_k, v| v.blank? }
  end

  # Removes all blank values from the +Hash+ in place and returns self.
  # Uses Object#blank? for determining if a value is blank.
  #
  #    h = { a: "", b: 1, c: nil, d: [], e: false, f: true }
  #    h.compact_blank!
  #    # => { b: 1, f: true }
  def compact_blank!
    # use delete_if rather than reject! because it always returns self even if nothing changed
    delete_if { |_k, v| v.blank? }
  end
end

class Range #:nodoc:
  # Optimize range sum to use arithmetic progression if a block is not given and
  # we have a range of numeric values.
  def sum(identity = nil)
    if block_given? || !(first.is_a?(Integer) && last.is_a?(Integer))
      super
    else
      actual_last = exclude_end? ? (last - 1) : last
      if actual_last >= first
        sum = identity || 0
        sum + (actual_last - first + 1) * (actual_last + first) / 2
      else
        identity || 0
      end
    end
  end
end

# Using Refinements here in order not to expose our internal method
using Module.new {
  refine Array do
    alias :orig_sum :sum
  end
}

class Array #:nodoc:
  # Array#sum was added in Ruby 2.4 but it only works with Numeric elements.
  def sum(init = nil, &block)
    if init.is_a?(Numeric) || first.is_a?(Numeric)
      init ||= 0
      orig_sum(init, &block)
    else
      super
    end
  end

  # Removes all blank elements from the +Array+ in place and returns self.
  # Uses Object#blank? for determining if an item is blank.
  #
  #    a = [1, "", nil, 2, " ", [], {}, false, true]
  #    a.compact_blank!
  #    # =>  [1, 2, true]
  def compact_blank!
    # use delete_if rather than reject! because it always returns self even if nothing changed
    delete_if(&:blank?)
  end
end

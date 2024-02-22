# typed: true

# DO NOT EDIT MANUALLY
# This file was pulled from a central RBI files repository.
# Please run `bin/tapioca annotations` to update it.

class ActiveJob::Base
  sig { params(blk: T.proc.bind(T.attached_class).params(job: T.attached_class).void).void }
  def self.after_discard(&blk); end

  sig { params(filters: T.untyped, blk: T.nilable(T.proc.bind(T.attached_class).params(job: T.attached_class).void)).void }
  def self.after_enqueue(*filters, &blk); end

  sig { params(filters: T.untyped, blk: T.nilable(T.proc.bind(T.attached_class).params(job: T.attached_class).void)).void }
  def self.after_perform(*filters, &blk); end

  sig { params(filters: T.untyped, blk: T.nilable(T.proc.bind(T.attached_class).params(job: T.attached_class, block: T.untyped).void)).void }
  def self.around_enqueue(*filters, &blk); end

  sig { params(filters: T.untyped, blk: T.nilable(T.proc.bind(T.attached_class).params(job: T.attached_class, block: T.untyped).void)).void }
  def self.around_perform(*filters, &blk); end

  sig { params(filters: T.untyped, blk: T.nilable(T.proc.bind(T.attached_class).params(job: T.attached_class).void)).void }
  def self.before_enqueue(*filters, &blk); end

  sig { params(filters: T.untyped, blk: T.nilable(T.proc.bind(T.attached_class).params(job: T.attached_class).void)).void }
  def self.before_perform(*filters, &blk); end

  sig { type_parameters(:ExceptionType).params(exceptions: T::Class[T.type_parameter(:ExceptionType)], block: T.nilable(T.proc.params(job: T.attached_class, error: T.type_parameter(:ExceptionType)).void)).void }
  sig { params(exceptions: String, block: T.nilable(T.proc.params(job: T.attached_class, error: T.untyped).void)).void }
  def self.discard_on(*exceptions, &block); end

  sig { params(klasses: T.any(Module, String), with: T.nilable(Symbol), block: T.nilable(T.proc.params(exception: T.untyped).void)).void }
  def self.rescue_from(*klasses, with: nil, &block); end

  sig { params(exceptions: T.any(Module, String), wait: T.any(ActiveSupport::Duration, Integer, Symbol, T.proc.params(executions: Integer).returns(Integer)), attempts: T.any(Integer, Symbol), queue: T.nilable(T.any(String, Symbol)), priority: T.untyped, jitter: Numeric, block: T.nilable(T.proc.params(job: T.attached_class, error: T.untyped).void)).void }
  def self.retry_on(*exceptions, wait: 3.seconds, attempts: 5, queue: nil, priority: nil, jitter: JITTER_DEFAULT, &block); end

  sig { params(part_name: T.nilable(T.any(String, Symbol)), block: T.nilable(T.proc.bind(T.attached_class).returns(T.untyped))).void }
  def self.queue_as(part_name = nil, &block); end

  sig { params(priority: T.untyped, block: T.nilable(T.proc.bind(T.attached_class).returns(T.untyped))).void }
  def self.queue_with_priority(priority = nil, &block); end
end

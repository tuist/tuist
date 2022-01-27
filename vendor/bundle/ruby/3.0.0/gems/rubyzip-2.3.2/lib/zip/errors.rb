module Zip
  class Error < StandardError; end
  class EntryExistsError < Error; end
  class DestinationFileExistsError < Error; end
  class CompressionMethodError < Error; end
  class EntryNameError < Error; end
  class EntrySizeError < Error; end
  class InternalError < Error; end
  class GPFBit3Error < Error; end
  class DecompressionError < Error; end

  # Backwards compatibility with v1 (delete in v2)
  ZipError = Error
  ZipEntryExistsError = EntryExistsError
  ZipDestinationFileExistsError = DestinationFileExistsError
  ZipCompressionMethodError = CompressionMethodError
  ZipEntryNameError = EntryNameError
  ZipInternalError = InternalError
end

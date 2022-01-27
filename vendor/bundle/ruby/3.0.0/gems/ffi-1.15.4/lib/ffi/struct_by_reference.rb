#
# Copyright (C) 2010 Wayne Meissner
#
# This file is part of ruby-ffi.
#
# All rights reserved.
#
# Redistribution and use in source and binary forms, with or without
# modification, are permitted provided that the following conditions are met:
#
# * Redistributions of source code must retain the above copyright notice, this
#   list of conditions and the following disclaimer.
# * Redistributions in binary form must reproduce the above copyright notice
#   this list of conditions and the following disclaimer in the documentation
#   and/or other materials provided with the distribution.
# * Neither the name of the Ruby FFI project nor the names of its contributors
#   may be used to endorse or promote products derived from this software
#   without specific prior written permission.
#
# THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
# AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
# IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
# DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT OWNER OR CONTRIBUTORS BE LIABLE
# FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL
# DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR
# SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER
# CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY,
# OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
# OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.#

module FFI
  # This class includes the {FFI::DataConverter} module.
  class StructByReference
    include DataConverter

    attr_reader :struct_class

    # @param [Struct] struct_class
    def initialize(struct_class)
      unless Class === struct_class and struct_class < FFI::Struct
        raise TypeError, 'wrong type (expected subclass of FFI::Struct)'
      end
      @struct_class = struct_class
    end

    # Always get {FFI::Type}::POINTER.
    def native_type
      FFI::Type::POINTER
    end

    # @param [nil, Struct] value
    # @param [nil] ctx
    # @return [AbstractMemory] Pointer on +value+.
    def to_native(value, ctx)
      return Pointer::NULL if value.nil?

      unless @struct_class === value
        raise TypeError, "wrong argument type #{value.class} (expected #{@struct_class})"
      end

      value.pointer
    end

    # @param [AbstractMemory] value
    # @param [nil] ctx
    # @return [Struct]
    # Create a struct from content of memory +value+.
    def from_native(value, ctx)
      @struct_class.new(value)
    end
  end
end

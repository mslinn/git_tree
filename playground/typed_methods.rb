require 'sorbet-runtime'
require 'typeprof' # For inference (optional; fallback to basic sigs if unavailable)

module TypedMethods
  def self.included(base)
    base.extend ClassMethods
  end

  module ClassMethods
    def method_added(name)
      # Guard against recursion on the callback itself
      return super if name == :method_added

      # Only target new instance methods
      return super unless private_instance_methods(false).include?(name) == false && instance_methods(false).include?(name)

      # Eject and rewrap the method with inferred sig (simplified; expand as needed)
      original_method = instance_method(name)
      remove_method(name)

      # Basic sig placeholder; in prod, parse TypeProf output for real inference
      inferred_params = original_method.parameters.map { |p| p.last == :rest ? T::Array[T.untyped] : T.untyped }
      define_method(name) do |*args, &block|
        sig { params(*inferred_params.zip(args).map { |t, a| T.untyped }, blk: T.untyped).returns(T.untyped) }
        original_method.bind_call(self, *args, &block)
      end

      # Chain to parent's method_added for standard behavior
      super
    end
  end
end

# Usage remains the same
# class GitTreeWalker
#   include Logging
#   include TypedMethods # Auto-sigs on def

#   def process(&)
#     # Your code; sig injected dynamically
#   end
# end

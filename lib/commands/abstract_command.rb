require 'optparse'
require 'rainbow/refinement'
require_relative '../util/git_tree_walker'

module GitTree
  class AbstractCommand
    using Rainbow

    class << self
      attr_accessor :allow_empty_args
    end

    def initialize(args)
      @options = {
        # Default to NORMAL verbosity
        verbosity: GitTreeWalker::NORMAL,
      }
      # The parse_options method is expected to be defined in the subclass
      # and should call super to get the base OptionParser instance.
      @args = parse_options(args)

      # Show help if no arguments are provided, which is a common requirement.
      help if @args.empty? && !self.class.allow_empty_args
    end

    def run
      raise NotImplementedError, "#{self.class.name} must implement the 'run' method."
    end

    private

    # Subclasses must implement this to provide their specific help text.
    def help
      raise NotImplementedError, "#{self.class.name} must implement the 'help' method."
    end

    # Provides a base OptionParser. Subclasses will add their specific options.
    def parse_options(args)
      parser = OptionParser.new do |opts|
        opts.on("-h", "--help", "Show this help message and exit.") do
          help
        end
        opts.on("-q", "--quiet", "Suppress normal output, only show errors.") do
          @options[:verbosity] = GitTreeWalker::QUIET
        end
        opts.on("-v", "--verbose", "Increase verbosity. Can be used multiple times (e.g., -v, -vv).") do
          @options[:verbosity] = case @options[:verbosity]
                                 when GitTreeWalker::NORMAL then GitTreeWalker::VERBOSE
                                 else GitTreeWalker::DEBUG
                                 end
        end
        yield opts if block_given?
      end
      parser.parse!(args)
    end
  end
end

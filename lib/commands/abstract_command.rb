require 'optparse'
require_relative '../util/git_tree_walker'
require_relative '../util/log'

module GitTree
  class AbstractCommand
    include Logging

    class << self
      attr_accessor :allow_empty_args
    end

    def initialize(args = ARGV, options: {})
      @raw_args = args
      @options = { serial: false }.merge(options)
    end

    # This method should be called after initialize to parse options
    # and finalize setup. This makes testing easier by allowing dependency
    # injection before options are parsed.
    def setup
      @args = parse_options(@raw_args)
      # Show help if no arguments are provided, unless allow_empty_args is set.
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
          Logging.verbosity = QUIET
        end
        opts.on("-v", "--verbose", "Increase verbosity. Can be used multiple times (e.g., -v, -vv).") do
          Logging.verbosity = case Logging.verbosity
                              when NORMAL then VERBOSE
                              else DEBUG
                              end
        end
        opts.on('-s', "--serial", "Run tasks serially in a single thread in the order specified.") do
          @options[:serial] = true
        end
        yield opts if block_given?
      end
      parser.parse!(args)
    end

    protected

    # @param dir [String] path to a git repository
    # @return [Boolean] true if the repository has changes, false otherwise.
    def repo_has_changes?(dir)
      repo = Rugged::Repository.new(dir)
      repo.status { |_path, _status| return true }
      false
    end
  end
end

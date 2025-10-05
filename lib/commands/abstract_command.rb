require 'optparse'
require_relative '../util/config'
require_relative '../util/log'

module GitTree
  # Abstract base class for all git-tree commands.
  # It handles common option parsing for verbosity and help.
  class AbstractCommand
    include Logging

    class << self
      attr_accessor :allow_empty_args
    end

    def initialize(args = ARGV, options: {})
      @args = args
      @options = options
      @config = GitTree::Config.new
      # Set initial verbosity from config before anything else happens.
      Logging.verbosity = @config.verbosity
    end

    # Common setup for all commands.
    # Parses options and sets initial verbosity.
    def setup
      # CLI options can override the config verbosity.
      parse_options(@args)
    end

    private

    # Parses common options like -h, -q, -v.
    # This method can be extended by subclasses by passing a block.
    def parse_options(args)
      parser = OptionParser.new do |opts|
        opts.on("-h", "--help", "Show this help message and exit") do
          help
        end

        opts.on("-q", "--quiet", "Suppress normal output, only show errors") do
          Logging.verbosity = ::Logging::QUIET
        end

        opts.on("-s", "--serial", "Run tasks serially in a single thread") do
          @options[:serial] = true
        end

        opts.on("-v", "--verbose", "Increase verbosity. Can be used multiple times.") do
          Logging.verbosity += 1
        end

        yield(opts) if block_given?
      end

      parser.parse!(args)
      help("No arguments are allowed") if !self.class.allow_empty_args && args.empty?
      args
    end
  end
end

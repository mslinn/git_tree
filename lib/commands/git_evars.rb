require_relative '../git_tree'
require 'rainbow/refinement'
require_relative 'abstract_command'

require_relative '../util/git_tree_walker'
require_relative '../util/zowee_optimizer'

using Rainbow

module GitTree
  class EvarsCommand < GitTree::AbstractCommand
    self.allow_empty_args = true

    def initialize(args)
      $PROGRAM_NAME = 'git-evars'
      super
    end

    def run
      result = []
      if @options[:zowee]
        walker = GitTreeWalker.new(@args, options: @options)
        all_paths = []
        walker.find_and_process_repos do |dir, _|
          all_paths << dir
        end
        optimizer = ZoweeOptimizer.new(walker.root_map)
        result = optimizer.optimize(all_paths, walker.display_roots)
      elsif @args.empty? # No args provided, use default roots and substitute them in the output
        walker = GitTreeWalker.new([], options: @options)
        walker.find_and_process_repos do |dir, _root_arg|
          result << make_env_var_with_substitution(dir, GitTreeWalker::DEFAULT_ROOTS)
        end
      else # Args were provided, process them as roots
        processed_args = @args.flat_map { |arg| arg.strip.split(/\s+/) }
        processed_args.each { |root| result.concat(process_root(root)) }
      end
      log_stdout result.join("\n") unless result.empty?
    end

    private

    # @param path [String] The path to convert to an environment variable name.
    # @return [String] The converted environment variable name.
    def env_var_name(path)
      name = path.include?('/') ? File.basename(path) : path
      name.tr(' ', '_').tr('-', '_')
    end

    # @param msg [String] The error message to display before the help text.
    # @return [nil]
    def help(msg = nil)
      warn "Error: #{msg}\n".red if msg
      warn <<~END_HELP
        #{$PROGRAM_NAME} - Generate bash environment variables for each git repository found under specified directory trees.

        Examines trees of git repositories and writes a bash script to STDOUT.
        If no directories are given, uses default environment variables (#{GitTreeWalker::DEFAULT_ROOTS.join(', ')}) as roots.
        These environment variables point to roots of git repository trees to walk.
        Skips directories containing a .ignore file, and all subdirectories.

        Does not redefine existing environment variables; messages are written to STDERR to indicate environment variables that are not redefined.

        Environment variables that point to the roots of git repository trees must have been exported, for example:

          $ export work=$HOME/work

        Usage: #{$PROGRAM_NAME} [OPTIONS] [ROOTS...]

        Options:
          -h, --help           Show this help message and exit.
          -q, --quiet          Suppress normal output, only show errors.
          -z, --zowee          Optimize variable definitions for size.
          -v, --verbose        Increase verbosity. Can be used multiple times (e.g., -v, -vv).

        ROOTS can be directory names or environment variable references enclosed within single quotes (e.g., '$work').
        Multiple roots can be specified in a single quoted string.

        Usage examples:
        $ #{$PROGRAM_NAME}                 # Use default environment variables as roots
        $ #{$PROGRAM_NAME} '$work $sites'  # Use specific environment variables
      END_HELP
      exit 1
    end

    # @param args [Array<String>] The command-line arguments.
    # @return [Array<String>] The parsed options.
    def parse_options(args)
      @args = super do |opts|
        opts.on("-z", "--zowee", "Optimize variable definitions for size.") do
          @options[:zowee] = true
        end
      end
    end

    # @param root [String] The root environment variable reference (e.g., '$work').
    # @return [Array<String>] An array of environment variable definitions.
    def process_root(root)
      help("Environment variable reference must start with a dollar sign ($).") unless root.start_with? '$'

      base = GemSupport.expand_env(root)
      help("Environment variable '#{root}' is undefined.") if base.nil? || base.strip.empty?
      help("Environment variable '#{root}' points to a non-existant directory (#{base}).") unless File.exist?(base)
      help("Environment variable '#{root}' points to a file (#{base}), not a directory.") unless Dir.exist?(base)

      result = [make_env_var(env_var_name(base), GemSupport.deref_symlink(base))]
      walker = GitTreeWalker.new([root], options: @options)
      walker.find_and_process_repos do |dir|
        relative_dir = dir.sub(base + '/', '')
        result << make_env_var(env_var_name(relative_dir), "#{root}/#{relative_dir}")
      end
      result
    end

    # @param name [String] The name of the environment variable.
    # @param value [String] The value of the environment variable.
    # @return [String] The environment variable definition string.
    def make_env_var(name, value)
      "export #{env_var_name(name)}=#{value}"
    end

    # Find which root this dir belongs to and substitute it.
    # @param dir [String] The directory path to process.
    # @param roots [Array<String>] An array of root environment variable names (e.g., ['work', 'sites']).
    # @return [String] The environment variable definition string, or nil if no root matches.
    def make_env_var_with_substitution(dir, roots)
      found_root_var = nil
      found_root_path = nil

      roots.each do |root_name|
        root_path = ENV.fetch(root_name, nil)
        next if root_path.nil? || root_path.strip.empty?

        next unless dir.start_with?(root_path)

        found_root_var = "$#{root_name}"
        found_root_path = root_path
        break
      end

      if found_root_var
        relative_dir = dir.sub(found_root_path + '/', '')
        make_env_var(env_var_name(relative_dir), "#{found_root_var}/#{relative_dir}")
      else
        # Fallback to absolute path if no root matches (should be rare).
        make_env_var(env_var_name(dir), dir)
      end
    end
  end
end

if $PROGRAM_NAME == __FILE__ || $PROGRAM_NAME.end_with?('git-evars')
  begin
    GitTree::EvarsCommand.new(ARGV).run
  rescue Interrupt
    log_stderr NORMAL, "\nInterrupted by user", :yellow
    exit! 130 # Use exit! to prevent further exceptions on shutdown
  rescue StandardError => e
    log_stderr QUIET, "#{e.class}: #{e.message}\n#{e.backtrace.join("\n")}", :red
    exit 1
  end
end

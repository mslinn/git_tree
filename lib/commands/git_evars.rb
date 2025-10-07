module GitTree
  class EvarsCommand < GitTree::AbstractCommand
    self.allow_empty_args = true

    def initialize(args = ARGV, options: {})
      raise TypeError, "args must be an Array, but got #{args.class}" unless args.is_a?(Array)
      raise TypeError, "options must be a Hash, but got #{options.class}" unless options.is_a?(Hash)

      $PROGRAM_NAME = 'git-evars'
      super
    end

    def run
      setup
      result = []
      walker = GitTreeWalker.new(@args, options: @options)
      if @options[:zowee]
        all_paths = []
        walker.find_and_process_repos do |dir, _root_arg|
          raise "dir cannot be nil in find_and_process_repos block" if dir.nil?
          raise TypeError, "dir must be a String in find_and_process_repos block, but got #{dir.class}" unless dir.is_a?(String)

          all_paths << dir
        end
        optimizer = ZoweeOptimizer.new(walker.root_map)
        result = optimizer.optimize(all_paths, walker.display_roots)
      else
        walker.find_and_process_repos do |dir, root_arg|
          raise ArgumentError, "dir cannot be nil in find_and_process_repos block" if dir.nil?
          raise ArgumentError, "root_arg cannot be nil in find_and_process_repos block" if root_arg.nil?
          raise TypeError, "dir must be a String in find_and_process_repos block, but it was a #{dir.class}" unless dir.is_a?(String)
          raise TypeError, "root_arg must be a String in find_and_process_repos block, but it was a #{root_arg.class}" unless root_arg.is_a?(String)

          result << make_env_var_with_substitution(dir, [root_arg.tr("'$", '')])
        end
      end
      Logging.log_stdout result.join("\n") unless result.empty?
    end

    private

    # construct an environment variable name from a path
    # @param path [String] The path to convert to an environment variable name.
    # @return [String] The converted environment variable name.
    def env_var_name(path)
      raise TypeError, "path must be a String, but it was a #{path.class}" unless path.is_a?(String)

      name = path.include?('/') ? File.basename(path) : path
      name.tr(' ', '_').tr('-', '_')
    end

    # @param msg [String] The error message to display before the help text.
    # @return [nil]
    def help(msg = nil)
      raise TypeError, "msg must be a String or nil, but got #{msg.class}" unless msg.is_a?(String) || msg.nil?

      Logging.log(Logging::QUIET, "Error: #{msg}\n", :red) if msg
      Logging.log Logging::QUIET, <<~END_HELP
        #{$PROGRAM_NAME} - Generate bash environment variables for each git repository found under specified directory trees.

        Examines trees of git repositories and writes a bash script to STDOUT.
        If no directories are given, uses default roots (#{@config.default_roots.join(', ')}) as roots.
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
      raise ArgumentError, "root was not specified" unless root
      raise TypeError, "root must be a String, but got #{root.class}" unless root.is_a?(String)

      help("Environment variable reference must start with a dollar sign ($).") unless root.start_with? '$'

      base = GemSupport.expand_env root
      help("Environment variable '#{root}' is undefined.") if base.nil? || base.strip.empty?
      help("Environment variable '#{root}' points to a non-existant directory (#{base}).") unless File.exist?(base)
      help("Environment variable '#{root}' points to a file (#{base}), not a directory.") unless Dir.exist?(base)

      result = [make_env_var(env_var_name(base), GemSupport.deref_symlink(base).to_s)]
      walker = GitTreeWalker.new([root], options: @options)
      walker.find_and_process_repos do |dir, _root_arg|
        raise "dir cannot be nil in find_and_process_repos block" if dir.nil?

        relative_dir = dir.sub(base + '/', '')
        result << make_env_var(env_var_name(relative_dir), "#{root}/#{relative_dir}")
      end
      result
    end

    # @param name [String] The name of the environment variable.
    # @param value [String] The value of the environment variable.
    # @return [String] The environment variable definition string.
    def make_env_var(name, value)
      raise ArgumentError, "name was not specified" unless name
      raise ArgumentError, "value was not specified" unless value
      raise TypeError, "name must be a String, but got #{name.class}" unless name.is_a?(String)
      raise TypeError, "value must be a String, but got #{value.class}" unless value.is_a?(String)

      "export #{env_var_name(name)}=#{value}"
    end

    # Find which root this dir belongs to and substitute it.
    # @param dir [String] The directory path to process.
    # @param roots [Array<String>] An array of root environment variable names (e.g., ['work', 'sites']).
    # @return [String] The environment variable definition string, or nil if no root matches.
    def make_env_var_with_substitution(dir, roots)
      raise ArgumentError, "dir was not specified" unless dir
      raise ArgumentError, "roots was not specified" unless roots
      raise TypeError, "dir must be a String, but got #{dir.class}" unless dir.is_a?(String)
      raise TypeError, "roots must be an Array, but got #{roots.class}" unless roots.is_a?(Array)

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
      else # Fallback to absolute path if no root matches (should be rare).
        make_env_var(env_var_name(dir), dir)
      end
    end
  end
end

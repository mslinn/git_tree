require_relative '../git_tree'

module GitTree
  class ReplicateCommand < GitTree::AbstractCommand
    self.allow_empty_args = true

    def initialize(args = ARGV, options: {})
      raise ArgumentError, "args must be an Array, but got #{args.class}" unless args.is_a?(Array)
      raise ArgumentError, "options must be a Hash, but got #{options.class}" unless options.is_a?(Hash)

      $PROGRAM_NAME = 'git-replicate'
      super
    end

    # @return [nil]
    def run
      setup
      result = []
      walker = GitTreeWalker.new(@args, options: @options)
      walker.find_and_process_repos do |dir, root_arg|
        raise "dir cannot be nil in find_and_process_repos block" if dir.nil?
        raise "root_arg cannot be nil in find_and_process_repos block" if root_arg.nil?

        raise TypeError, "dir must be a String in find_and_process_repos block, but got #{dir.class}" unless dir.is_a?(String)
        raise TypeError, "root_arg must be a String in find_and_process_repos block, but got #{root_arg.class}" unless root_arg.is_a?(String)

        result << replicate_one(dir, root_arg)
      end
      Logging.log_stdout result.join("\n") unless result.empty?
    end

    private

    def help(msg = nil)
      raise TypeError, "msg must be a String or nil, but got #{msg.class}" unless msg.is_a?(String) || msg.nil?

      Logging.log(Logging::QUIET, "Error: #{msg}\n", :red) if msg
      Logging.log Logging::QUIET, <<~END_HELP
        #{$PROGRAM_NAME} - Replicates trees of git repositories and writes a bash script to STDOUT.
        If no directories are given, uses default roots (#{@config.default_roots.join(', ')}) as roots.
        The script clones the repositories and replicates any remotes.
        Skips directories containing a .ignore file.

        Options:
          -h, --help           Show this help message and exit.
          -q, --quiet          Suppress normal output, only show errors.
          -v, --verbose        Increase verbosity. Can be used multiple times (e.g., -v, -vv).

        Usage: #{$PROGRAM_NAME} [OPTIONS] [ROOTS...]

        ROOTS can be directory names or environment variable references (e.g., '$work').
        Multiple roots can be specified in a single quoted string.

        Usage examples:
        $ #{$PROGRAM_NAME} '$work'
        $ #{$PROGRAM_NAME} '$work $sites'
      END_HELP
      exit! 1
    end

    def replicate_one(dir, root_arg)
      raise TypeError, "dir must be a String, but got #{dir.class}" unless dir.is_a?(String)
      raise TypeError, "root_arg must be a String, but got #{root_arg.class}" unless root_arg.is_a?(String)

      output = []
      config_path = File.join(dir, '.git', 'config')
      return output unless File.exist?(config_path)

      config = Rugged::Config.new(config_path)
      origin_url = config['remote.origin.url']
      return output unless origin_url

      base_path = File.expand_path(ENV.fetch(root_arg.tr("'$", ''), ''))
      relative_dir = dir.sub(base_path + '/', '')

      output << "if [ ! -d \"#{relative_dir}/.git\" ]; then"
      output << "  mkdir -p '#{File.dirname(relative_dir)}'"
      output << "  pushd '#{File.dirname(relative_dir)}' > /dev/null"
      output << "  git clone '#{origin_url}' '#{File.basename(relative_dir)}'"
      config.each_key do |key|
        next unless key.start_with?('remote.') && key.end_with?('.url')

        remote_name = key.split('.')[1]
        next if remote_name == 'origin'

        output << "  git remote add #{remote_name} '#{config[key]}'"
      end
      output << '  popd > /dev/null'
      output << 'fi'
      output
    end
  end
end

if $PROGRAM_NAME == __FILE__ || $PROGRAM_NAME.end_with?('git-replicate') # Corrected from git-tree-replicate
  begin
    GitTree::ReplicateCommand.new(ARGV).run
  rescue Interrupt
    Logging.log Logging::NORMAL, "\nInterrupted by user", :yellow
    exit! 130 # Use exit! to prevent further exceptions on shutdown
  rescue StandardError => e
    Logging.log Logging::QUIET, "#{e.class}: #{e.message}\n#{e.backtrace.join("\n")}", :red
    exit! 1
  end
end

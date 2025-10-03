require_relative '../git_tree'
require 'rainbow/refinement'
require_relative 'abstract_command'
require_relative '../util/git_tree_walker'

using Rainbow

module GitTree
  class ReplicateCommand < GitTree::AbstractCommand
    self.allow_empty_args = true

    def initialize(args)
      $PROGRAM_NAME = 'git-replicate' # Corrected from git-tree-replicate
      super
    end

    def run
      result = []
      walker = GitTreeWalker.new(@args, options: @options)
      # Use the public API to find repos, which now yields the root argument as well.
      walker.find_and_process_repos { |dir, root_arg| result << replicate_one(dir, root_arg) }

      puts result.join("\n")
    end

    private

    def help(msg = nil)
      warn "Error: #{msg}\n".red if msg
      warn <<~END_HELP
        #{$PROGRAM_NAME} - Replicates trees of git repositories and writes a bash script to STDOUT.
        If no directories are given, uses default environment variables ('sites', 'sitesUbuntu', 'work') as roots.
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
      exit 1
    end

    def replicate_one(dir, root_arg)
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
    warn "\nInterrupted by user".yellow
    exit! 130 # Use exit! to prevent further exceptions on shutdown
  rescue StandardError => e
    puts "An unexpected error occurred: #{e.message}".red
    exit 1
  end
end

require_relative '../git_tree'
require 'rainbow/refinement'
require_relative 'abstract_command'
require_relative '../util/git_tree_walker'

module GitTree
  using Rainbow

  class ReplicateCommand < AbstractCommand
    def initialize(args)
      $PROGRAM_NAME = 'git-replicate'
      super
    end

    def run
      help('At least one root must be specified.') if @args.empty?

      result = []
      walker = GitTreeWalker.new(@args, verbosity: @options[:verbosity])
      # Use the public API to find repos, which now yields the root argument as well.
      walker.find_and_process_repos { |dir, root_arg| result << replicate_one(dir, root_arg) }

      puts result.join("\n")
    end

    private

    def help(msg = nil)
      warn "Error: #{msg}\n".red if msg
      warn <<~END_HELP
        #{$PROGRAM_NAME} - Replicates trees of git repositories and writes a bash script to STDOUT.
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
      repo = Rugged::Repository.new(dir)
      origin_url = repo.config['remote.origin.url']
      # ARGV[0] is not reliable here, use the arg passed to run

      warn "Warning: Uncommitted changes in #{dir}. These will not be replicated.".yellow if repo_has_changes?(dir)
      base_path = File.expand_path(ENV.fetch(root_arg.tr("'$", ''), ''))
      relative_dir = dir.sub(base_path + '/', '')

      output << "if [ ! -d \"#{relative_dir}/.git\" ]; then"
      output << "  mkdir -p '#{File.dirname(relative_dir)}'"
      output << "  pushd '#{File.dirname(relative_dir)}' > /dev/null"
      output << "  git clone #{origin_url} '#{File.basename(relative_dir)}'"
      repo.remotes.each do |remote|
        next if remote.name == 'origin'

        output << "  git remote add #{remote.name} '#{remote.url}'"
      end
      output << '  popd > /dev/null'
      output << 'fi'
      output
    end
  end
end

if $PROGRAM_NAME == __FILE__ || $PROGRAM_NAME.end_with?('git-replicate')
  begin
    GitTree::ReplicateCommand.new(ARGV).run
  rescue Interrupt
    warn "\nInterrupted by user".yellow
    exit 130
  rescue StandardError => e
    puts "An unexpected error occurred: #{e.message}".red
    exit 1
  end
end

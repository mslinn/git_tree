require_relative '../git_tree'
require 'rainbow/refinement'
require_relative 'abstract_command'
require_relative '../util/git_tree_walker'

module GitTree
  using Rainbow

  class ReplicateCommand < AbstractCommand
    def initialize(args)
      $PROGRAM_NAME = 'git-tree-replicate'
      super
    end

    def run
      root = @args[0]
      help("Error: Environment variable reference must start with a dollar sign ($)") unless root.start_with? '$'

      base = GemSupport.expand_env(root)
      help("Environment variable '#{root}' is undefined.") if base.strip.empty?
      help("Environment variable '#{root}' points to a non-existant directory (#{base}).") unless File.exist?(base)
      help("Environment variable '#{root}' points to a file (#{base}), not a directory.") unless Dir.exist?(base)

      result = []
      walker = GitTreeWalker.new(@args)
      walker.find_and_process_repos do |dir|
        result << replicate_one(dir, root)
      end

      puts result.join("\n")
    end

    private

    def help(msg = nil)
      warn "Error: #{msg}\n".red if msg
      warn <<~END_HELP
        #{$PROGRAM_NAME} - Replicates a tree of git repositories and writes a bash script
        to STDOUT that clones the repositories in the tree. Replicates any remotes
        defined in the source repositories to the target repositories.

        The environment variable must have been exported, for example:

        $ export work=$HOME/work

        Directories containing a file called .ignore are ignored.

        Usage example:
        Assuming that 'work' is an environment variable that contains the name of a
        directory that contains a tree of git repositories:

        $ #{$PROGRAM_NAME} '$work'

        The name of the environment variable must be preceded by a dollar sign and enclosed within single quotes.
      END_HELP
      exit 1
    end

    def replicate_one(dir, root_arg)
      output = []
      repo = Rugged::Repository.new(dir)
      origin_url = repo.config['remote.origin.url']
      # ARGV[0] is not reliable here, use the arg passed to run
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

  if $PROGRAM_NAME == __FILE__ || $PROGRAM_NAME.end_with?('git-tree-replicate')
    begin
      GitTree::ReplicateCommand.new(ARGV).run
    rescue StandardError => e
      puts "An unexpected error occurred: #{e.message}".red
      exit 1
    end
  end
end

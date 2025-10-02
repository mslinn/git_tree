require_relative '../git_tree'
require 'rainbow/refinement'
require_relative 'abstract_command'
require_relative '../util/git_tree_walker'

module GitTree
  using Rainbow

  class EvarsCommand < AbstractCommand
    def initialize(args)
      $PROGRAM_NAME = 'git-tree-evars'
      super
    end

    def run
      root = @args[0]
      help("Environment variable reference must start with a dollar sign ($).") unless root.start_with? '$'

      base = GemSupport.expand_env(root)
      help("Environment variable '#{root}' is undefined.") if base.strip.empty?
      help("Environment variable '#{root}' points to a non-existant directory (#{base}).") unless File.exist?(base)
      help("Environment variable '#{root}' points to a file (#{base}), not a directory.") unless Dir.exist?(base)

      result = []
      result << make_env_var(env_var_name(base), GemSupport.deref_symlink(base))

      walker = GitTreeWalker.new(@args)
      walker.find_and_process_repos do |dir|
        relative_dir = dir.sub(base + '/', '')
        result << make_env_var(env_var_name(relative_dir), "#{root}/#{relative_dir}")
      end

      puts result.map { |x| "#{x}\n" }.join
    end

    private

    def env_var_name(path)
      name = path.include?('/') ? File.basename(path) : path
      name.tr(' ', '_').tr('-', '_')
    end

    def help(msg = nil)
      warn "Error: #{msg}\n".red if msg
      warn <<~END_HELP
        #{$PROGRAM_NAME} - Examines a tree of git repositories and writes a bash script to STDOUT
        that defines environment variables which point to the repositories in the tree.

        Purpose: Quickly generate bash environment variables for each git repository found under a specified directory tree.

        Does not redefine existing environment variables; messages are written to
        STDERR to indicate environment variables that are not redefined.

        The environment variable must have been exported, for example:

        $ export work=$HOME/work

        Directories containing a file called .ignore are ignored.

        Usage example:

        $ #{$PROGRAM_NAME} '$work'

        The name of the environment variable must be preceded by a dollar sign and enclosed within single quotes.
      END_HELP
      exit 1
    end

    def make_env_var(name, value)
      "export #{env_var_name(name)}=#{value}"
    end
  end

  if $PROGRAM_NAME == __FILE__ || $PROGRAM_NAME.end_with?('git-tree-evars')
    begin
      GitTree::EvarsCommand.new(ARGV).run
    rescue StandardError => e
      puts "An unexpected error occurred: #{e.message}".red
      exit 1
    end
  end
end

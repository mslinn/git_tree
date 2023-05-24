require_relative 'git_tree'

module GitTree
  # @param root might be "$envar" or a fully qualified directory name ("/a/b/c")
  def self.command_evars(root = ARGV[0])
    abort "Error: Argument must start with a dollar sign ($)" unless root.start_with? '$'

    base = MslinnUtil.expand_env root
    dirs = directories_to_process base

    # puts "# root=#{root}, base=#{base}"
    puts make_env_vars root, base, dirs
  end

  def self.help_evars(msg = nil)
    puts msg if msg
    puts <<~END_HELP
      Examines a tree of git repos and writes a bash script to STDOUT that defines environment variables that point to the repos in the tree.

      Directories containing a file called .ignore are ignored.
    END_HELP
    exit 1
  end
end

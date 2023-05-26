require_relative 'git_tree'

module GitTree
  using Rainbow

  # @param root might be "$envar" or a fully qualified directory name ("/a/b/c")
  def self.command_replicate(root = ARGV[0])
    help_replicate "Environment variable reference was missing. Please enclose it within single quotes." if root.to_s.empty?
    help_replicate "Error: Environment variable reference must start with a dollar sign ($)" unless root.start_with? '$'

    base = MslinnUtil.expand_env root
    help_replicate "Environment variable '#{root}' is undefined." if base.strip.empty?
    help_replicate "Environment variable '#{root}' points to a non-existant directory (#{base})." unless File.exist?(base)
    help_replicate "Environment variable '#{root}' points to a file (#{base}), not a directory." unless Dir.exist?(base)

    dirs = directories_to_process base

    # puts "# root=#{root}, base=#{base}"
    puts make_replicate_script root, base, dirs
  end

  def self.help_replicate(msg = nil)
    prog_name = File.basename $PROGRAM_NAME
    puts "Error: #{msg}\n".red if msg
    puts <<~END_HELP
      #{prog_name} - Replicates a tree of git repositories and writes a bash script
      to STDOUT that clones the repositories in the tree. Replicates any remotes
      defined in the source repositories to the target repositories.

      The environment variable must have been exported, for example:

      $ export work=$HOME/work

      Directories containing a file called .ignore are ignored.

      Usage example:
      Assuming that 'work' is an environment variable that contains the name of a
      directory that contains a tree of git repositories:

      $ #{prog_name} '$work'

      The name of the environment variable must be preceded by a dollar sign and enclosed within single quotes.
    END_HELP
    exit 1
  end

  # @param root should be an "$envar" that points to the root of a directory tree containing git repos.
  # @param base a fully qualified directory name ("/a/b/c")
  # @param dirs directory list to process
  def self.make_replicate_script(root, base, dirs)
    help_replicate "Error: Please specify the subdirectory to traverse.\n\n" if root.to_s.empty?

    Dir.chdir(base) do
      result = dirs.map { |dir| replicate_one(dir) }
      result.join "\n"
    end
  end

  def self.replicate_one(dir)
    output = []
    project_dir = File.basename dir
    parent_dir = File.dirname dir
    repo = Rugged::Repository.new dir
    origin_url = repo.config['remote.origin.url']

    output << "if [ ! -d \"#{dir}/.git\" ]; then"
    output << "  mkdir -p '#{parent_dir}'"
    output << "  pushd '#{parent_dir}' > /dev/null"
    output << "  git clone #{origin_url}"

    repo.remotes.each do |remote|
      next if remote.name == 'origin' || remote.url == 'no_push'

      output << "  git remote add #{remote.name} '#{remote.url}'"
    end

    output << '  popd > /dev/null'

    # git_dir_name = File.basename Dir.pwd
    # if git_dir_name != project_dir
    #   output << '  # Git project directory was renamed, renaming this copy to match original directory structure'
    #   output << "  mv #{git_dir_name} #{project_dir}"
    # end
    output << "fi"
    output << ''
    output
  end
end

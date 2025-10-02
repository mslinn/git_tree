require_relative '../git_tree'

module GitTree
  using Rainbow

  # @param root might be "$envar" or a fully qualified directory name ("/a/b/c")
  def self.command_evars(root = ARGV[0])
    help_evars "Environment variable reference was missing. Please enclose it within single quotes." if root.to_s.empty?
    help_evars "Environment variable reference must start with a dollar sign ($)." unless root.start_with? '$'

    base = MslinnUtil.expand_env root
    help_evars "Environment variable '#{root}' is undefined." if base.strip.empty?
    help_evars "Environment variable '#{root}' points to a non-existant directory (#{base})." unless File.exist?(base)
    help_evars "Environment variable '#{root}' points to a file (#{base}), not a directory." unless Dir.exist?(base)

    dirs = directories_to_process base
    puts make_env_vars(root, base, dirs)
  end

  def self.env_var_name(path)
    name = path.include?('/') ? File.basename(path) : path
    name.tr(' ', '_').tr('-', '_')
  end

  def self.help_evars(msg = nil)
    prog_name = File.basename $PROGRAM_NAME
    puts "Error: #{msg}\n".red if msg
    puts <<~END_HELP
      #{prog_name} - Examines a tree of git repositories and writes a bash script to STDOUT
      that defines environment variables which point to the repositories in the tree.

      Purpose: Quickly generate bash environment variables for each git repository found under a specified directory tree.

      Does not redefine existing environment variables; messages are written to
      STDERR to indicate environment variables that are not redefined.

      The environment variable must have been exported, for example:

      $ export work=$HOME/work

      Directories containing a file called .ignore are ignored.

      Usage example:

      $ #{prog_name} '$work'

      The name of the environment variable must be preceded by a dollar sign and enclosed within single quotes.
    END_HELP
    exit 1
  end

  def self.make_env_var(name, value)
    "export #{env_var_name(name)}=#{value}"
  end

  # @param root should be an "$envar" that points to the root of a directory tree containing git repos.
  # @param base a fully qualified directory name ("/a/b/c")
  # @param dirs directory list to process
  def self.make_env_vars(root, base, dirs)
    help_evars "Error: Please specify the subdirectory to traverse." if root.to_s.empty?

    result = []
    result << make_env_var(env_var_name(base), MslinnUtil.deref_symlink(base))
    dirs.each do |dir|
      ename = env_var_name dir
      ename_value = MslinnUtil.expand_env "$#{ename}"
      ename_value = ename_value.gsub(' ', '\\ ').delete_prefix('\\') unless ename_value.empty?
      if ename_value.to_s.strip.empty?
        result << make_env_var(ename, "#{root}/#{dir}")
      else
        msg = "$#{ename} was previously defined as #{ename_value}"
        dir2 = MslinnUtil.expand_env(ename_value)
        if Dir.exist? dir2
          warn msg.cyan
        else
          msg += ", but that directory does not exist,\n  so redefining #{ename} as #{dir}."
          warn msg.green
          result << make_env_var(ename, "#{root}/#{dir}")
        end
      end
    end
    result.map { |x| "#{x}\n" }.join + "\n"
  end
end

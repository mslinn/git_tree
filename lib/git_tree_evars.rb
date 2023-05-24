require 'shellwords'
require_relative 'git_tree'

module GitTree
  using Rainbow

  # @param root might be "$envar" or a fully qualified directory name ("/a/b/c")
  def self.command_evars(root = ARGV[0])
    abort "Error: Argument must start with a dollar sign ($)".red unless root.start_with? '$'

    base = MslinnUtil.expand_env root
    dirs = directories_to_process base

    # puts "# root=#{root}, base=#{base}"
    puts make_env_vars root, base, dirs
  end

  def self.env_var_name(path)
    name = path.include?('/') ? File.basename(path) : path
    name.tr(' ', '_').tr('-', '_')
  end

  def self.help_evars(msg = nil)
    puts msg if msg
    puts <<~END_HELP
      Examines a tree of git repos and writes a bash script to STDOUT that defines environment variables that point to the repos in the tree.
      Does not redefine existing environment variables.

      Directories containing a file called .ignore are ignored.
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
    help_evars "Error: Please specify the subdirectory to traverse.\n\n" if root.to_s.empty?

    result = []
    result << make_env_var(env_var_name(base), MslinnUtil.deref_symlink(base))
    dirs.each do |dir|
      ename = env_var_name dir
      ename_value = MslinnUtil.expand_env("$#{ename}")
      ename_value = ename_value.shellescape.delete_prefix('\\') unless ename_value.empty?
      if ename_value.to_s.empty?
        result << make_env_var(ename, "#{root}/#{dir}")
      else
        warn "$#{ename} was previously defined as #{ename_value}".yellow
      end
    end
    result.map { |x| "#{x}\n" }.join
  end
end

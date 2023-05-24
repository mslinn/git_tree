module GitTree
  require 'find'
  require 'rugged'
  require_relative 'util'

  # @return array containing directory names to process
  #   Each directory name ends with a slash, to ensure symlinks are dereferences
  def self.directories_to_process(root)
    root_fq = File.expand_path root
    abort "Error: #{root_fq} is a file, instead of a directory. Cannot recurse." if File.file? root_fq

    root_fq = MslinnUtil.deref_symlink(root_fq).to_s
    abort "Error: #{root_fq} does not exist. Halting." unless Dir.exist? root_fq

    result = []
    Find.find(root_fq) do |path|
      next if File.file? path

      Find.prune if File.exist?("#{path}/.ignore")

      if Dir.exist?("#{path}/.git")
        result << path.to_s
        Find.prune
      end
    end
    result.map { |x| x.delete_prefix("#{root_fq}/") }
  end

  def self.env_var_name(path)
    name = path.include?('/') ? File.basename(path) : path
    name.tr(' ', '_').tr('-', '_')
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
      result << make_env_var(env_var_name(dir), "#{root}/#{dir}")
    end
    result.map { |x| "#{x}\n" }.join
  end
end

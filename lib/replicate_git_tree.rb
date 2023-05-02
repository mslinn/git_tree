module ReplicateGitTree
  require 'find'
  require 'rugged'

  # @return Path
  def self.deref_symlink(symlink)
    require 'pathname'
    Pathname.new(symlink).realpath
  end

  def self.do_one(dir)
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

  # @return array containing directory names to process
  #   Each directory name ends with a slash, to ensure symlinks are dereferences
  def self.directories_to_process(root)
    root_fq = File.expand_path root
    abort "Error: #{root_fq} is a file, instead of a directory. Cannot recurse." if File.file? root_fq

    root_fq = deref_symlink(root_fq).to_s
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

  def self.ensure_ends_with(string, suffix)
    string = string.delete_suffix suffix
    "#{string}#{suffix}"
  end

  def self.expand_env(str)
    str.gsub(/\$([a-zA-Z_][a-zA-Z0-9_]*)|\${\g<1>}|%\g<1>%/) do
      ENV.fetch(Regexp.last_match(1), nil)
    end
  end

  def self.help(msg = nil)
    puts msg if msg
    puts <<~END_HELP
      Replicates tree of git repos and writes a bash script to STDOUT that clones the repos in the tree.
      Adds upstream remotes as required.

      Directories containing a file called .ignore are ignored.
    END_HELP
    exit 1
  end

  def self.make_env_var(name, value)
    "export #{env_var_name(name)}=#{value}"
  end

  def self.env_var_name(path)
    name = path.include?('/') ? File.basename(path) : path
    name.tr(' ', '_')
  end

  def self.make_env_vars(base, dirs)
    result = []
    result << "cat <<EOF > #{base}/.evars"
    result << make_env_var(env_var_name(base), deref_symlink(base))
    dirs.each do |dir|
      result << make_env_var(env_var_name(dir), "$#{base}/#{dir}")
    end
    result << "EOF\n"
    result.join "\n"
  end

  def self.make_script(root, base, dirs)
    help "Error: Please specify the subdirectory to traverse.\n\n" if root.to_s.empty?

    Dir.chdir(base) do
      result = dirs.map { |dir| do_one(dir) }
      result.join "\n"
    end
  end

  def self.run(root = ARGV[0])
    base = expand_env root
    dirs = directories_to_process base

    puts make_script root, base, dirs
    puts make_env_vars base, dirs
  end
end

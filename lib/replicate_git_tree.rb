module ReplicateGitTree
  require 'find'
  require 'rugged'

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

  def self.do_one(dir)
    output = []
    project_dir = File.basename dir
    parent_dir = File.dirname dir
    repo = Rugged::Repository.new dir
    origin_url = repo.config['remote.origin.url']

    output << "mkdir -p '#{parent_dir}'"
    output << "pushd '#{parent_dir}' > /dev/null"
    output << "git clone #{origin_url}"

    repo.remotes.each do |remote|
      next if remote.name == 'origin' || remote.url == 'no_push'

      output << "git remote add #{remote.name} '#{remote.url}'"
    end

    output << 'popd > /dev/null'

    # git_dir_name = File.basename Dir.pwd
    # if git_dir_name != project_dir
    #   output << '# Git project directory was renamed, renaming this copy to match original directory structure'
    #   output << "mv #{git_dir_name} #{project_dir}"
    # end
    output << ''
    output
  end

  def self.directories_to_process(root)
    root_fq = File.expand_path root
    abort "Error: #{root_fq} does not exist" unless File.exist? root_fq

    result = []
    Find.find(root_fq) do |path|
      next unless File.directory? path

      ignore_path = "#{path}/.ignore"
      if File.exist?(ignore_path)
        Find.prune
      else
        git_path = "#{path}/.git"
        if File.exist? git_path
          result << path
          Find.prune
        end
      end
    end

    parent_fq = File.dirname root_fq
    result.map { |x| x.delete_prefix "#{parent_fq}/" }
  end

  help "Error: Please specify the subdirectory to traverse.\n\n" if ARGV.empty?
  base = expand_env ARGV[0]
  dirs = directories_to_process base
  result = dirs.map { |dir| do_one(dir) }
  puts result.join "\n"
end

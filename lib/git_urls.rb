#!/usr/bin/env ruby

require 'rugged'

def expand_env(str)
  str.gsub(/\$([a-zA-Z_][a-zA-Z0-9_]*)|\${\g<1>}|%\g<1>%/) do
    ENV.fetch(Regexp.last_match(1), nil)
  end
end

def help(msg = nil)
  puts msg if msg
  puts <<~END_HELP
    Replicates tree of git repos and writes a bash script to STDOUT that clones the repos in the tree.
    Adds upstream remotes as required.

    Directories containing a file called .ignore are ignored.
  END_HELP
  exit 1
end

def do_one(clone_dir)
  output = []
  Dir.chdir(clone_dir) do
    project_dir = File.basename clone_dir
    repo = Rugged::Repository.new(clone_dir)
    origin_url = repo.config['remote.origin.url']
    parent_dir = File.expand_path('..', clone_dir)
    output << "mkdir -p '#{parent_dir}'"
    output << "pushd '#{parent_dir}' > /dev/null"
    output << "git clone #{origin_url}"

    upstream_url = repo.config['remote.upstream.url']
    if upstream_url && origin_url != 'no_push'
      output << "cd #{project_dir}"
      output << "git remote add upstream '#{upstream_url}'"
    end

    output << 'popd > /dev/null'

    git_dir_name = File.basename Dir.pwd
    if git_dir_name != project_dir
      output << '# Git project directory was renamed, renaming this copy to match original directory structure'
      output << "mv #{git_dir_name} #{project_dir}"
    end
    output << ''
    output
  end
end

help "Error: Please specify the subdirectory to traverse.\n\n" if ARGV.empty?
base = expand_env ARGV[0]
dirs = Dir["#{base}/**/.git"]
result = dirs.map do |dir|
  clone_dir = File.expand_path '..', dir
  do_one(clone_dir) unless File.exist? "clone_dir/.ignore"
end
result.join "\n"

require 'fileutils'
require 'rugged'

ROOT = 'demo'.freeze

def make_repo(path)
  git_dir = "#{ROOT}/#{path}"
  puts "Making git repo at #{git_dir}"

  FileUtils.mkdir_p git_dir
  repo = Rugged::Repository.init_at git_dir

  basename = File.basename path
  repo.remotes.create 'origin', "git@github.com:mslinn/#{basename}.git"
  return unless path.end_with?('a', 'b')

  repo.remotes.create 'upstream', "git@github.com:mslinn/#{basename}_upstream.git"
end

%w[a b c].each do |x|
  make_repo "proj_#{x}"
end
FileUtils.touch "#{ROOT}/proj_c/.ignore"

%w[d e f].each do |x|
  make_repo "sub1/proj_#{x}"
end

%w[g h i].each do |x|
  make_repo "sub2/proj_#{x}"
end
FileUtils.touch "#{ROOT}/sub2/.ignore"

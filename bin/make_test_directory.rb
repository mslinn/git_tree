require 'fileutils'

ROOT = 'demo'

def make_repo(path)
  basename = File.basename path
  git_dir = "#{ROOT}/#{path}"
  FileUtils.mkdir_p git_dir
  repo = Rugged::Repository.init_at git_dir
  repo.remotes.create 'origin', "git@github.com:mslinn/#{basename}.git"
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

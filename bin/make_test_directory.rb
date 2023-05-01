require 'fileutils'

ROOT = 'demo'

def make_repo(path)
  git_dir = "#{ROOT}/#{path}/.git"
  FileUtils.mkdir_p git_dir
  FileUtils.touch "#{git_dir}/.gitkeep"
  basename = File.basename path
  content = <<~END_CONFIG
    [core]
        repositoryformatversion = 0
        filemode = true
        bare = false
        logallrefupdates = true
    [remote "origin"]
        url = git@github.com:mslinn/#{basename}.git
        fetch = +refs/heads/*:refs/remotes/origin/*
  END_CONFIG
  File.write "#{ROOT}/#{path}/.git/config", content
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

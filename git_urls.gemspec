require_relative 'lib/git_urls/version'

Gem::Specification.new do |spec|
  github = 'https://github.com/mslinn/git_urls'

  spec.authors = ['Mike Slinn']
  spec.bindir = 'exe'
  spec.description = <<~END_OF_DESC
    Scans a git directory tree and writes out a script that clones the repos in the tree, 
    and adds upstream remotes as required. 
    Directories containing a file called .ignore are ignored.
  END_OF_DESC
  spec.email = ['mslinn@mslinn.com']
  spec.files = Dir['.rubocop.yml', 'LICENSE.*', 'Rakefile', '{lib,spec}/**/*', '*.gemspec', '*.md']
  spec.homepage = 'https://www.mslinn.com/git/1100-git-tree.html'
  spec.license = 'MIT'
  spec.metadata = {
    'allowed_push_host' => 'https://rubygems.org',
    'bug_tracker_uri'   => "#{github}/issues",
    'changelog_uri'     => "#{github}/CHANGELOG.md",
    'homepage_uri'      => spec.homepage,
    'source_code_uri'   => github,
  }
  spec.name = 'git_urls'
  spec.post_install_message = <<~END_MESSAGE

    Thanks for installing #{spec.name}!

  END_MESSAGE
  spec.require_paths = ['lib']
  spec.required_ruby_version = '>= 2.6.0'
  spec.summary = 'Scans a git directory tree and writes out a script that clones the repos in the tree.'
  spec.test_files = spec.files.grep(%r!^(test|spec|features)/!)
  spec.version = JekyllNthVersion::VERSION

  spec.add_dependency 'rugged'
end

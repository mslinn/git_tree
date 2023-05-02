require_relative 'lib/replicate_git_tree/version'

Gem::Specification.new do |spec| # rubocop:disable Metrics/BlockLength
  github = 'https://github.com/mslinn/replicate_git_tree'

  spec.authors = ['Mike Slinn']
  spec.bindir = 'bindir'
  spec.description = <<~END_OF_DESC
    Scans a git directory tree and writes out a script that clones the repos in the tree,
    and adds upstream remotes as required.
    Directories containing a file called .ignore are ignored.
  END_OF_DESC
  spec.email = ['mslinn@mslinn.com']
  spec.executables = ['replicate_git_tree']
  spec.files = Dir[
    '{bindir,lib}/**/*',
    '.rubocop.yml',
    'LICENSE.*',
    'Rakefile',
    '*.gemspec',
    '*.md'
  ]
  spec.homepage = 'https://www.mslinn.com/git/1100-git-tree.html'
  spec.license = 'MIT'
  spec.metadata = {
    'allowed_push_host' => 'https://rubygems.org',
    'bug_tracker_uri'   => "#{github}/issues",
    'changelog_uri'     => "#{github}/CHANGELOG.md",
    'homepage_uri'      => spec.homepage,
    'source_code_uri'   => github,
  }
  spec.name = 'replicate_git_tree'
  spec.post_install_message = <<~END_MESSAGE

    Thanks for installing #{spec.name}!

  END_MESSAGE
  spec.required_ruby_version = '>= 2.6.0'
  spec.summary = 'Scans a git directory tree and writes out a script that clones the repos in the tree.'
  spec.version = GitUrlsVersion::VERSION

  spec.add_dependency 'rugged'
end

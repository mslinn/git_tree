require_relative 'lib/git_tree/version'

Gem::Specification.new do |spec| # rubocop:disable Metrics/BlockLength
  github = 'https://github.com/mslinn/git_tree'

  spec.authors     = ['Mike Slinn']
  spec.bindir      = 'exe'
  spec.description = <<~END_OF_DESC
    Installs 5 commands that process a git directory tree.
    Directories containing a file called .ignore are ignored.

    The git-commitAll command commits all changes to each repository in the tree.

    The git-evars command writes a script that defines environment variables pointing to git repos.

    The git-exec command executes a bash expression on children of a directory, or a list of directories.

    The git-replicate command writes a script that clones the repos in the tree,
    and adds any defined remotes.

    The git-update command updates each repository in the tree.
  END_OF_DESC
  spec.email       = ['mslinn@mslinn.com']
  spec.executables = %w[git-commitAll git-evars git-exec git-replicate git-update]
  spec.files = Dir[
    '{exe,lib}/**/*',
    '.rubocop.yml',
    'LICENSE.*',
    'Rakefile',
    '*.gemspec',
    '*.md'
  ]
  spec.homepage = 'https://www.mslinn.com/git/1100-git-tree.html'
  spec.license  = 'MIT'
  spec.metadata = {
    'allowed_push_host' => 'https://rubygems.org',
    'bug_tracker_uri'   => "#{github}/issues",
    'changelog_uri'     => "#{github}/CHANGELOG.md",
    'homepage_uri'      => spec.homepage,
    'source_code_uri'   => github,
  }
  spec.name                 = 'git_tree'
  spec.platform             = Gem::Platform::RUBY
  spec.post_install_message = <<~END_MESSAGE

    Thanks for installing #{spec.name}!

  END_MESSAGE
  spec.required_ruby_version = '>= 3.2.0'
  spec.summary               = 'Installs five commands that walk a git directory tree and perform tasks.'
  spec.version               = GitUrlsVersion::VERSION

  spec.add_dependency 'gem_support'
  spec.add_dependency 'rainbow'
  spec.add_dependency 'rugged'
end

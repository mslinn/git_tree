require 'gem_support'
require 'rainbow/refinement'
require_relative 'git_tree/version'

module GitTree
  using Rainbow

  # Helper to require all .rb files in a subdirectory
  def self.require_all(relative_path)
    Dir[File.join(__dir__, relative_path, '*.rb')].sort.each { |file| require file }
  end

  # Make logging methods available at the module level (e.g., GitTree.log_stderr)
  extend Logging

  # Require utilities first, as commands may depend on them.
  require_all 'util'
  require_all 'commands'
end

require 'gem_support'
require 'rainbow/refinement'
require_relative 'git_tree/version'

def self.require_all(relative_path)
  Dir[File.join(__dir__, relative_path, '*.rb')].each { |file| require file }
end

require_all 'commands'
require_all 'util'

require 'highline'
require 'yaml'
require_relative '../git_tree'

module GitTree
  # A command to interactively create a user-level configuration file.
  class TreeconfigCommand
    def initialize
      $PROGRAM_NAME = 'git-treeconfig'
      @highline = HighLine.new
      @config_path = GitTree::GTConfig.default_config_path
      @existing_config = File.exist?(@config_path) ? YAML.load_file(@config_path) : {}
    end

    def run
      @highline.say <<~END_MSG
        Welcome to git-tree configuration.
        This utility will help you create a configuration file at #{@config_path}
        You can press Enter to accept default values presented within brackets.

      END_MSG

      defaults = GitTree::GTConfig.new

      new_config = {}
      new_config['git_timeout'] = @highline.ask("Git command timeout in seconds? ", Integer) do |q|
        q.default = @existing_config.fetch('git_timeout', defaults.git_timeout)
      end

      new_config['verbosity'] = @highline.ask("Default verbosity level (0=quiet, 1=normal, 2=verbose, 3=debug)? ", Integer) do |q|
        q.default = @existing_config.fetch('verbosity', defaults.verbosity)
        q.in = 0..::Logging.DEBUG
      end

      roots_str = @highline.ask("Default root directories (space-separated)? ", String) do |q|
        q.default = @existing_config.fetch('default_roots', defaults.default_roots).join(' ')
      end
      new_config['default_roots'] = roots_str.split

      File.write(@config_path, new_config.to_yaml)

      @highline.say "\nConfiguration saved to #{@config_path}", :green
    end
  end
end

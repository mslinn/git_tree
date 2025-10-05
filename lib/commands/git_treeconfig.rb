require 'highline'
require 'yaml'
require_relative '../util/config'
require_relative '../util/log'

module GitTree
  # A command to interactively create a user-level configuration file.
  class TreeconfigCommand
    def initialize
      $PROGRAM_NAME = 'git-treeconfig'
      @cli = HighLine.new
      @config_path = GitTree::Config.default_config_path
      @existing_config = File.exist?(@config_path) ? YAML.load_file(@config_path) : {}
    end

    def run
      @cli.say "Welcome to git-tree configuration."
      @cli.say "This utility will help you create a configuration file at: #{@config_path}"
      @cli.say "Press Enter to accept the default value in brackets."
      @cli.say ""

      defaults = GitTree::Config.new

      new_config = {}
      new_config['git_timeout'] = @cli.ask("Git command timeout in seconds? ", Integer) do |q|
        q.default = @existing_config.fetch('git_timeout', defaults.git_timeout)
      end

      new_config['verbosity'] = @cli.ask("Default verbosity level (0=quiet, 1=normal, 2=verbose)? ", Integer) do |q|
        q.default = @existing_config.fetch('verbosity', defaults.verbosity)
        q.in = 0..2
      end

      roots_str = @cli.ask("Default root directories (space-separated)? ", String) do |q|
        q.default = @existing_config.fetch('default_roots', defaults.default_roots).join(' ')
      end
      new_config['default_roots'] = roots_str.split

      File.write(@config_path, new_config.to_yaml)

      @cli.say ""
      @cli.say "Configuration saved to #{@config_path}", :green
    end
  end
end

if $PROGRAM_NAME == __FILE__ || $PROGRAM_NAME.end_with?('git-treeconfig')
  begin
    GitTree::TreeconfigCommand.new.run
  rescue Interrupt
    # Using HighLine, a simple newline is enough on interrupt.
    puts "\n"
    exit 130
  rescue StandardError => e
    Logging.log(Logging::QUIET, "An error occurred: #{e.message}", :red)
    exit 1
  end
end

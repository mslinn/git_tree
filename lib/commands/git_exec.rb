require 'open3'
require 'pathname'
require 'rainbow/refinement'
require_relative 'abstract_command'
require_relative '../util/git_tree_walker'
require_relative '../util/thread_pool_manager'

module GitTree
  using Rainbow

  class ExecCommand < AbstractCommand
    def initialize(args)
      $PROGRAM_NAME = 'git-exec'
      super
    end

    def run
      help('At least one root and a command must be specified.') if @args.length < 2

      roots = @args[0..-2]
      command = @args[-1]

      walker = GitTreeWalker.new(roots, verbosity: @options[:verbosity])
      walker.process do |worker, dir, _thread_id, _git_walker_instance|
        execute(worker, dir, command)
      end
    end

    private

    def execute(worker, dir, command)
      # Use system with :chdir to be thread-safe, avoiding process-wide Dir.chdir.
      # Redirect stdout and stderr to capture the output.
      output, status = Open3.capture2e(command, chdir: dir)
      if status.success?
        worker.log_stdout(output.strip) unless output.strip.empty?
      else
        worker.log_stderr(output.strip.red) unless output.strip.empty?
      end
    rescue StandardError => e
      warn "Error: '#{e.message}' from executing '#{command}' in #{dir}".red
    end

    def help(msg = nil)
      warn "Error: #{msg}\n".red if msg
      warn <<~END_HELP
        #{$PROGRAM_NAME} - Executes an arbitrary shell command for each repository.

        If no arguments are given, uses default environment variables ('sites', 'sitesUbuntu', 'work') as roots.
        These environment variables point to roots of git repository trees to walk.
        Skips directories containing a .ignore file, and all subdirectories.

        Environment variables that point to the roots of git repository trees must have been exported, for example:

          $ export work=$HOME/work

        Usage: #{$PROGRAM_NAME} [OPTIONS] TLD_ROOT SHELL_COMMAND


        TLD_ROOT: Points to the top-level directory to process. 3 forms are accepted:
          1. A directory name, which may be relative or absolute.
          2. An environment variable reference,
             which must be preceded by a dollar sign and enclosed within single quotes
             to prevent expansion by the shell.
          3. A list of directory names, which may be relative or absolute,
             and may contain environment variables.

        Usage examples:
        1) For all git repositories under $sites, display their root directories:
           $ #{$PROGRAM_NAME} '$sites' pwd

        2) For all subdirectories of the current directory, update `Gemfile.lock` and install a local copy of the gem:
           $ #{$PROGRAM_NAME} . 'bundle && bundle update && rake install'

        3) For all subdirectories of the directory pointed to by `$work`, run git commit and push changes.
           This is a simplified version of the `git-commitAll` command.
           $ #{$PROGRAM_NAME} '$work' 'git commit -am "-" && git push'

        4) For all git repositories under the current directory, list the fully qualified path to the `demo/` subdirectory, if it exists.
           $ #{$PROGRAM_NAME} '. ~ $my_plugins' 'if [ -d demo ]; then realpath demo; fi'
      END_HELP
      exit 1
    end
  end

if $PROGRAM_NAME == __FILE__ || $PROGRAM_NAME.end_with?('git-exec')
  begin
    GitTree::ExecCommand.new(ARGV).run
  rescue Interrupt
    warn "\nInterrupted by user".yellow
    exit 130
  rescue StandardError => e
    puts "An unexpected error occurred: #{e.message}".red
    exit 1
  end
end

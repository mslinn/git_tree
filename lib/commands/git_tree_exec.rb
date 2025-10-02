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
      $PROGRAM_NAME = 'git-tree-exec'
      super
    end

    def run
      help("A command must be specified.") if @args.length == 1

      root = @args[0]
      command = @args[1]

      walker = GitTreeWalker.new([root], verbosity: @options[:verbosity])
      walker.process do |worker, dir, _thread_id, _git_walker_instance|
        execute(worker, dir, command)
      end
    end

    private

    def execute(worker, dir, command)
      # Use system with :chdir to be thread-safe, avoiding process-wide Dir.chdir.
      # Redirect stdout and stderr to capture the output.
      output, _status = Open3.capture2e(command, chdir: dir)
      worker.log_stdout(output.strip) unless output.strip.empty?
    rescue StandardError => e
      warn "Error: '#{e.message}' from executing '#{command}' in #{dir}".red
    end

    def help(msg = nil)
      warn "Error: #{msg}\n".red if msg
      warn <<~END_HELP
        #{$PROGRAM_NAME} - requires two parameters.
        The first points to the top-level directory to process. 3 forms are accepted.
          1. A directory name, which may be relative or absolute.
          2. An environment variable reference,
             which must be preceded by a dollar sign and enclosed within single quotes
             to prevent expansion by the shell.
          3. A list of directory names, which may be relative or absolute,
             and may contain environment variables.

        The environment variable must have been exported, for example:

          $ export work=$HOME/work

        Directories containing a file called .ignore are ignored.

        Usage examples:
        1) For all subdirectories of the current directory, update `Gemfile.lock` and install a local copy of the gem:
           $ #{$PROGRAM_NAME} . 'bundle && bundle update && rake install'

        2) For all subdirectories of the directory pointed to by `$work`, run git commit and push changes.
           $ #{$PROGRAM_NAME} '$work' 'git commit -am "-" && git push'

        3) For all subdirectories of the specified directories, list the projects that have a demo/ subdirectory.
           $ #{$PROGRAM_NAME} '. ~ $my_plugins' 'if [ -d demo]; then realpath demo; fi'
      END_HELP
      exit 1
    end
  end

  if $PROGRAM_NAME == __FILE__ || $PROGRAM_NAME.end_with?('git-tree-exec')
    begin
      GitTree::ExecCommand.new(ARGV).run
    rescue StandardError => e
      puts "An unexpected error occurred: #{e.message}".red
      exit 1
    end
  end
end

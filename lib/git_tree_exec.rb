require 'pathname'
require 'shellwords'
require_relative 'git_tree'

module GitTree
  using Rainbow

  # @param root might be:
  #   - '$envar'
  #   - A fully qualified directory name ("/a/b/c")
  #   - A list of either of the above
  def self.command_exec(args = ARGV)
    root = args[0]
    command = args[1]

    help_exec "A directory specification and a command must be specified." if args.empty?
    help_exec "A command must be specified." if args.length == 1

    base = MslinnUtil.expand_env root
    help_exec "Environment variable '#{root}' is undefined." if base.empty?
    base.shellsplit.each do |top|
      dirs = directories_to_process(top)
      dirs.each do |dir|
        dir = File.join(base, dir) if Pathname.new(dir).relative?
        execute dir, command
      end
    end
  end

  # @return array containing status code and result of running command in the given directory
  # @param command [String] Shell command to execute
  def self.execute(dir, command)
    Dir.chdir(dir) do
      unless File.exist? dir
        warn "Warning: directory '#{dir}' does not exist.".yellow
        return
      end
      unless Dir.exist? dir
        warn "Warning: #{dir} is a file, not a directory.".yellow
        return
      end
      result = `#{command}`.rstrip
      puts result unless result.empty?
    end
  rescue StandardError => e
    warn "Error: #{e.message} from executing '#{command}' in #{dir}".red
  end

  def self.help_exec(msg = nil)
    prog_name = File.basename $PROGRAM_NAME
    puts "Error: #{msg}\n".red if msg
    puts <<~END_HELP
      #{prog_name} - requires only one parameter,
      which points to the top-level directory to process.
      3 forms are accepted.
      Only direct child directories are processed; infinite recursion is not supported.
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

      1) For all subdirectories of the current directory,
         update `Gemfile.lock` and install a local copy of the gem:

         $ #{prog_name} . 'bundle && bundle update && rake install'


      2) For all subdirectories of the directory pointed to by `$work`,
         run git commit and push changes.

         $ #{prog_name} '$work' 'git commit -am "-" && git push'


      3) For all subdirectories of the specified directories,
         list the projects that have a demo/ subdirectory.

         The specified directories are . (the current directory),
         ~ (the home directory) and the directory pointed to by $my_plugins

         $ #{prog_name} '. ~ $my_plugins' 'if [ -d demo]; then realpath demo; fi'
    END_HELP
    exit 1
  end
end

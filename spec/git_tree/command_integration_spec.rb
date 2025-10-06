require 'spec_helper'
require 'tmpdir'
require 'fileutils'
require 'open3'
require 'tempfile'

def dump_repo_history(repo_path, history_hash)
  return "No command history found for #{repo_path}.\n" unless history_hash.key?(repo_path)

  history = history_hash[repo_path]
  return "No commands recorded for #{repo_path}.\n" if history.empty?

  "Command history for #{repo_path}:\n" + history.map { |cmd| "  - #{cmd}" }.join("\n") + "\n"
end

module IoHelp
  def self.show_io(name, value)
    length = value ? value.length : 0
    "#{name} (#{length} characters): '#{value}'\n"
  end
end

RSpec::Matchers.define :be_successful do
  match do |actual|
    actual[:status].success?
  end

  failure_message do |actual|
    "expected command to be successful, but it failed.\n" +
      IoHelp.show_io('STDOUT', actual[:stdout]) +
      IoHelp.show_io('STDERR', actual[:stderr]) +
      IoHelp.show_io('STDAUX', actual[:stdaux])
  end
end

RSpec::Matchers.define :have_empty_stderr do
  match do |command_result|
    value = command_result[:stderr]
    value.nil? || value.strip.empty?
  end

  failure_message do |command_result| # actual is the same as command_result
    stderr = command_result[:stderr]
    message = if stderr&.empty?
                nil # "Expected stderr to be empty, and it was. This is not an error."
              elsif command_result[:stderr]&.strip&.empty?
                "Expected stderr to be empty, but it only contained whitespace."
              else
                "Expected stderr to be empty, but it contained '#{stderr}'\n"
              end
    "#{message}\n" +
      IoHelp.show_io('STDAUX', command_result[:stdaux]) +
      dump_repo_history(command_result[:repo_path_for_history], @repo_command_history)
    # ::IoHelp.show_io('STDOUT', command_result[:stdout])
  end
end

RSpec.describe 'Command-line Integration' do # rubocop:disable RSpec/DescribeClass
  # This spec tests the end-to-end functionality of the command-line executables.
  # It creates a real file system structure with git repositories and runs the
  # commands as a user would, capturing their output and verifying side effects.

  # --- Helper to run commands ---
  def run_command(command_string)
    # Point to the executables in the `exe` directory
    exe_path = File.expand_path('../../exe', __dir__)
    env = {
      'HOME'                 => @home_dir,
      'WORK'                 => @work_dir,
      'SITES'                => @sites_dir,
      'PATH'                 => "#{exe_path}:#{ENV.fetch('PATH', nil)}",
      'GIT_TREE_GIT_TIMEOUT' => '5', # Use a short timeout for integration tests
      'TREECONFIG_PATH'      => File.join(@home_dir, '.treeconfig.yml'),
    }

    # Use popen3 to capture stdout, stderr, and stdaux (fd 3)
    # We create a temporary file to capture stdaux (fd 3) separately from stdout.
    stdaux_file = Tempfile.new('stdaux')
    puts "Executing: #{command_string}"
    Open3.popen3(env, command_string, 3 => stdaux_file) do |stdin, stdout, stderr, wait_thr|
      stdin.close
      stdout_str = stdout.read
      stderr_str = stderr.read
      stdaux_file.rewind
      stdaux_str = stdaux_file.read
      result = { stdout: stdout_str, stderr: stderr_str, stdaux: stdaux_str, status: wait_thr.value }
      result[:repo_path_for_history] = @repo_clean_path # Default, can be overridden
      result
    end
  end

  # --- Git test environment setup ---
  def git(command, dir = @tmpdir)
    @repo_command_history[dir] << "git -C #{dir} #{command}"
    system('git', '-C', dir, *command.split, out: File::NULL, err: File::NULL)
  end

  def setup_repo(path, name)
    # Create a bare repo to act as the remote origin
    bare_repo_path = File.join(@tmpdir, 'remotes', "#{name}.git")
    FileUtils.mkdir_p(bare_repo_path)
    git("init --bare", bare_repo_path)

    # Clone it to create the working repo
    # We need to change directory to ensure the clone happens inside the tmpdir,
    # as the `path` is relative to the current working directory of the test runner.
    # By changing to @tmpdir first, we ensure the clone happens in the correct location.
    Dir.chdir(@tmpdir) { git("clone #{bare_repo_path} #{path}", '.') }

    # Initial commit
    git('config user.name "Test User"', path)
    git('config user.email "test@example.com"', path)
    File.write(File.join(path, 'README.md'), "This is #{name}")
    git('add README.md', path)
    git('commit -m "Initial commit"', path)
    git('push origin master', path)
  end

  before(:all) do # rubocop:disable RSpec/BeforeAfterAll
    # This setup runs once for the entire test file.
    # We need to use instance variables because `let` is not available in `before(:all)`.
    @tmpdir = Dir.mktmpdir('git_tree_integration_spec_all')
    @repo_command_history = Hash.new { |h, k| h[k] = [] }
    @home_dir = File.join(@tmpdir, 'home')
    @work_dir = File.join(@tmpdir, 'work')
    @sites_dir = File.join(@tmpdir, 'sites')

    # Ensure all git commands in this test environment default to the 'master' branch
    system('git', 'config', '--global', 'init.defaultBranch', 'master', out: File::NULL, err: File::NULL)

    FileUtils.mkdir_p([@home_dir, @work_dir, @sites_dir])

    # Create a default config file
    config_content = <<~YAML
      ---
      verbosity: 1
      default_roots:
      - $WORK
      - $SITES
    YAML
    File.write(File.join(@home_dir, '.treeconfig.yml'), config_content)

    # --- Create all the test repos ---
    @repo_clean_path = File.join(@work_dir, 'repo_clean')
    setup_repo(@repo_clean_path, 'repo_clean')

    # Repo with a modified file
    @repo_modified_path = File.join(@work_dir, 'repo_modified')
    setup_repo(@repo_modified_path, 'repo_modified')
    File.write(File.join(@repo_modified_path, 'README.md'), "This file has been modified.")

    # Repo with a new file
    @repo_new_file_path = File.join(@work_dir, 'repo_new_file')
    setup_repo(@repo_new_file_path, 'repo_new_file')
    File.write(File.join(@repo_new_file_path, 'new.txt'), "A new file.")

    # Repo with a deleted file
    @repo_deleted_file_path = File.join(@work_dir, 'repo_deleted_file')
    setup_repo(@repo_deleted_file_path, 'repo_deleted_file')
    FileUtils.rm(File.join(@repo_deleted_file_path, 'README.md'))

    # Repo with a detached HEAD
    @repo_detached_path = File.join(@sites_dir, 'repo_detached')
    setup_repo(@repo_detached_path, 'repo_detached')
    head_commit_sha = `git -C #{@repo_detached_path} rev-parse HEAD 2> /dev/null`.strip
    git("checkout #{head_commit_sha}", @repo_detached_path)

    # Empty repo with no commits
    @repo_empty_path = File.join(@sites_dir, 'repo_empty')
    setup_repo(@repo_empty_path, 'repo_empty') # This correctly creates a repo with a remote

    # Ignored repo
    ignored_dir = File.join(@work_dir, 'ignored_projects')
    FileUtils.mkdir_p(ignored_dir)
    FileUtils.touch(File.join(ignored_dir, '.ignore'))
    setup_repo(File.join(ignored_dir, 'repo_ignored'), 'repo_ignored')

    # --- Dynamically determine expected repo counts ---
    # These lists define which repos should be found by the walker in different scenarios.
    # The empty and ignored repos should not be processed by any command.
    @processable_work_repos = [@repo_clean_path, @repo_modified_path, @repo_new_file_path, @repo_deleted_file_path]
    @processable_sites_repos = [@repo_detached_path] # @repo_empty_path is not a valid repo for most operations
    @all_processable_repos = @processable_work_repos + @processable_sites_repos
  end

  after(:all) do # rubocop:disable RSpec/BeforeAfterAll
    FileUtils.remove_entry(@tmpdir)
  end

  describe 'git-exec' do
    subject(:result) { run_command(command) }

    context 'when run with default roots' do
      let(:command) { "git-exec pwd" }

      it 'succeeds' do
        expect(result).to be_successful
      end

      it 'yields empty stderr' do
        expect(result).to have_empty_stderr
      end

      it 'processes all processable repos' do
        actual_lines = result[:stdout].lines.map(&:strip).sort
        expected_lines = @all_processable_repos.sort
        expect(actual_lines.count).to eq(expected_lines.count), lambda {
          "Expected to process #{expected_lines.count} repos, but found #{actual_lines.count}.\n\n" +
            "Expected Repos:\n" + expected_lines.join("\n") + "\n\n" +
            "Actual Repos Found:\n" + actual_lines.join("\n")
        }
        expect(result[:stdout]).to include(@repo_modified_path)
        expect(result[:stdout]).not_to include(@repo_ignored_path)
      end
    end

    context 'when an invalid command is given' do
      let(:command) { "git-exec nonexistentcommand" }

      it 'succeeds' do
        expect(result).to be_successful
      end

      it 'logs an error to stderr' do
        expect(result[:stderr]).to include("Error: Command 'nonexistentcommand' not found")
      end
    end

    it 'respects the -q flag', skip: "TODO" do
      # This test is tricky because it requires modifying a file that is read by the subprocess.
      # For now, we trust the unit tests for option parsing.
    end

    context 'when run with an explicit root' do
      let(:command) { "git-exec '#{@work_dir}' pwd" }

      it 'succeeds' do
        expect(result).to be_successful
      end

      it 'yields empty stderr' do
        expect(result).to have_empty_stderr
      end

      it 'processes only repos under the specified root' do
        expect(result[:stdout].lines.count).to eq(@processable_work_repos.count)
        expect(result[:stdout]).not_to include(@repo_detached_path) # This repo is in @sites_dir
      end
    end

    context 'when an undefined environment variable is given as a root' do
      let(:command) { "git-exec '$UNDEFINED_VAR' pwd" }

      it 'exits with a non-zero status' do
        expect(result[:status].exitstatus).to eq(1)
      end

      it 'logs an error to stderr' do
        expect(result[:stderr]).to include("Environment variable '$UNDEFINED_VAR' is undefined.")
      end
    end
  end

  describe 'git-update' do
    context 'when remote is ahead' do
      subject(:result) { run_command("git-update '#{@work_dir}'") }

      let(:remote_path) { File.join(@tmpdir, 'remotes', 'repo_clean.git') }
      let(:local_repo_path) { File.join(@work_dir, 'repo_clean') }
      let(:new_remote_file) { File.join(local_repo_path, 'new_remote_file.txt') }

      before do
        # Add a new commit to the bare "remote" repo
        clone_path = File.join(@tmpdir, 'clone_for_commit')
        begin
          # Helper to run a command and raise an error with output on failure
          run_or_raise = lambda do |command, dir|
            stdout, stderr, status = Open3.capture3(*command, chdir: dir)
            raise "Setup command failed: '#{command.join(' ')}'\nSTDOUT:\n#{stdout}\nSTDERR:\n#{stderr}" unless status.success?
          end

          run_or_raise.call(['git', 'clone', remote_path, clone_path], @tmpdir)
          run_or_raise.call(['git', 'config', 'user.name', 'Test User'], clone_path)
          run_or_raise.call(['git', 'config', 'user.email', 'test@example.com'], clone_path)
          File.write(File.join(clone_path, 'new_remote_file.txt'), 'remote change')
          run_or_raise.call(['git', 'add', '.'], clone_path)
          run_or_raise.call(['git', 'commit', '--allow-empty', '-m', 'Remote commit'], clone_path)
          run_or_raise.call(%w[git push origin master], clone_path)

          # Verify the file exists in the bare repo's history
          remote_files = `git --git-dir=#{remote_path} ls-tree -r master --name-only`.split("\n")
          raise "Test setup failed: 'new_remote_file.txt' was not pushed to the bare repository." unless remote_files.include?('new_remote_file.txt')
        ensure
          FileUtils.rm_rf(clone_path)
        end
      end

      context 'when running the command' do
        before { result[:repo_path_for_history] = local_repo_path }

        it 'succeeds' do
          expect(result).to be_successful
        end

        it 'yields empty stderr' do
          expect(result).to have_empty_stderr
        end

        it 'pulls the new file into the local repository' do
          # Custom failure message to provide more context
          expect(File.exist?(new_remote_file)).to be(true), lambda {
            # Run the command inside the lambda to ensure the expectation is checked after the action
            result
            dir_listing = `ls -la #{local_repo_path}`.strip
            "Expected file '#{new_remote_file}' to exist, but it does not.\n\n" +
              "Directory listing for #{local_repo_path}:\n#{dir_listing}\n\n" +
              dump_repo_history(local_repo_path, @repo_command_history) +
              "\nCommand Output:\n" +
              IoHelp.show_io('STDOUT', result[:stdout]) +
              IoHelp.show_io('STDERR', result[:stderr]) +
              IoHelp.show_io('STDAUX', result[:stdaux])
          }
        end
      end
    end

    context 'when an undefined environment variable is given as a root' do
      subject(:result) { run_command("git-update '$UNDEFINED_VAR'") }

      before { @result = run_command("git-update '$UNDEFINED_VAR'") }

      it 'exits with a non-zero status' do
        expect(result[:status].exitstatus).to eq(1)
      end

      it 'logs an error to stderr' do
        expect(result[:stderr]).to include("Environment variable '$UNDEFINED_VAR' is undefined.")
      end
    end
  end

  describe 'git-replicate' do
    subject(:result) { run_command(command) }

    context 'when generating a replication script' do
      let(:command) { "git-replicate '$WORK'" }

      it 'succeeds and generates a non-empty script' do
        expect(result).to be_successful
        expect(result).to have_empty_stderr
        expect(result[:stdout]).not_to be_empty
      end

      it 'generates a script that can successfully clone the repositories' do
        # This test has a side effect (running a script), so it doesn't use the @result
        # from the before block to avoid re-running the command unnecessarily if other tests fail.
        script_gen_result = run_command("git-replicate '$WORK'")
        replication_script = script_gen_result[:stdout]

        replication_dir = Dir.mktmpdir('replication_target')
        File.write(File.join(replication_dir, 'replicate.sh'), replication_script)
        system("cd #{replication_dir} && bash ./replicate.sh", out: File::NULL, err: File::NULL)

        # Verify that the repos were cloned
        @processable_work_repos.each do |repo_path|
          repo_name = File.basename(repo_path)
          expect(Dir.exist?(File.join(replication_dir, repo_name, '.git'))).to be true
        end

        FileUtils.remove_entry(replication_dir)
      end
    end

    context 'when an undefined environment variable is given as a root' do
      let(:command) { "git-replicate '$UNDEFINED_VAR'" }

      it 'exits with a non-zero status' do
        expect(result[:status].exitstatus).to eq(1)
      end

      it 'logs an error to stderr' do
        expect(result[:stderr]).to include("Environment variable '$UNDEFINED_VAR' is undefined.")
      end
    end
  end

  describe 'git-evars' do
    context 'when generating evars for a specific root' do
      subject(:result) { run_command("git-evars '$WORK'") }

      before { @result = run_command("git-evars '$WORK'") }

      it 'succeeds' do
        expect(result).to be_successful
      end

      it 'yields empty stderr' do
        expect(result).to have_empty_stderr
      end

      it 'generates correct export statements' do
        expect(result[:stdout]).to include("export repo_clean=$WORK/repo_clean")
        expect(result[:stdout]).to include("export repo_modified=$WORK/repo_modified")
      end
    end

    context 'when an undefined environment variable is given as a root' do
      subject(:result) { run_command("git-evars '$UNDEFINED_VAR'") }

      before { @result = run_command("git-evars '$UNDEFINED_VAR'") }

      it 'exits with a non-zero status' do
        expect(result[:status].exitstatus).to eq(1)
      end

      it 'logs an error to stderr' do
        expect(result[:stderr]).to include("Environment variable '$UNDEFINED_VAR' is undefined.")
      end
    end
  end

  fdescribe 'git-commitAll' do
    context 'when committing changes' do
      it 'succeeds and commits all changes' do
        result = run_command('git-commitAll -m "Test commit"')
        expect(result).to be_successful

        # Check that the modified file was committed
        log_output = `git -C #{@repo_modified_path} log -1 --pretty=%B 2> /dev/null`.strip
        expect(log_output).to eq("Test commit")

        # Check that the new file was committed
        log_output = `git -C #{@repo_new_file_path} log -1 --pretty=%B 2> /dev/null`.strip
        expect(log_output).to eq("Test commit")

        # Check that the deleted file was committed
        log_output = `git -C #{@repo_deleted_file_path} log -1 --pretty=%B 2> /dev/null`.strip
        expect(log_output).to eq("Test commit")
      end
    end

    context 'when a repository has a detached HEAD' do
      subject(:result) { run_command('git-commitAll -v -m "Test commit"') }

      it 'succeeds' do
        expect(result).to be_successful
      end

      it 'yields empty stderr' do
        expect(result).to have_empty_stderr
      end

      it 'logs a skip message to stdaux' do
        expect(result[:stdaux]).to include("Skipping #{@repo_detached_path} because it is in a detached HEAD state")
      end
    end

    context 'when an undefined environment variable is given as a root' do
      subject(:result) { run_command("git-commitAll '$UNDEFINED_VAR'") }

      it 'exits with a non-zero status' do
        expect(result[:status].exitstatus).to eq(1)
      end

      it 'logs an error to stderr' do
        expect(result[:stderr]).to include("Environment variable '$UNDEFINED_VAR' is undefined.")
      end
    end
  end
end

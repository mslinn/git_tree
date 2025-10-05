require 'spec_helper'
require 'tmpdir'
require 'fileutils'
require 'open3'

RSpec::Matchers.define :be_successful do
  match do |actual|
    actual[:status].success?
  end

  failure_message do |actual|
    "expected command to be successful, but it failed.\n" \
      "STDOUT:\n#{actual[:stdout]}\n" \
      "STDERR:\n#{actual[:stderr]}"
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
      'GIT_TREE_GIT_TIMEOUT' => '15', # Use a short timeout for integration tests
    }
    stdout, stderr, status = Open3.capture3(env, command_string)
    { stdout: stdout, stderr: stderr, status: status }
  end

  # --- Git test environment setup ---
  def git(command, dir = @tmpdir)
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
    git('push origin main', path)
  end

  before(:all) do # rubocop:disable RSpec/BeforeAfterAll
    # This setup runs once for the entire test file.
    # We need to use instance variables because `let` is not available in `before(:all)`.
    @tmpdir = Dir.mktmpdir('git_tree_integration_spec_all')
    @home_dir = File.join(@tmpdir, 'home')
    @work_dir = File.join(@tmpdir, 'work')
    @sites_dir = File.join(@tmpdir, 'sites')

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
    FileUtils.mkdir_p(@repo_empty_path)
    git("init", @repo_empty_path)

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
    context 'when run with default roots' do
      it 'succeeds' do
        result = run_command("git-exec pwd")
        expect(result).to be_successful
      end

      it 'processes all processable repos' do
        result = run_command("git-exec pwd")
        expect(result[:stdout].lines.count).to eq(@all_processable_repos.count)
        expect(result[:stdout]).to include(@repo_modified_path)
        expect(result[:stdout]).not_to include(@repo_ignored_path)
      end
    end

    it 'handles an invalid command' do
      result = run_command("git-exec nonexistentcommand")
      expect(result).to be_successful # The tool itself succeeds
      expect(result[:stderr]).to include("Error: Command 'nonexistentcommand' not found")
    end

    it 'respects the -q flag' do
      # Create a config with high verbosity
      File.write(File.join(@home_dir, '.treeconfig.yml'), "verbosity: 2")
      result = run_command("git-exec -q pwd")
      expect(result[:stderr]).to be_empty
    end

    context 'when run with an explicit root' do
      it 'succeeds' do
        result = run_command("git-exec '#{@work_dir}' pwd")
        expect(result).to be_successful
      end

      it 'processes only repos under the specified root' do
        result = run_command("git-exec '#{@work_dir}' pwd")
        expect(result[:stdout].lines.count).to eq(@processable_work_repos.count)
        expect(result[:stdout]).not_to include(@repo_detached_path) # This repo is in @sites_dir
      end
    end

    it 'handles an undefined environment variable gracefully' do
      result = run_command("git-exec '$UNDEFINED_VAR' pwd")
      expect(result[:status].exitstatus).to eq(1)
      expect(result[:stderr]).to include("Environment variable '$UNDEFINED_VAR' is undefined.")
    end
  end

  describe 'git-update' do
    context 'when remote is ahead' do
      let(:remote_path) { File.join(@tmpdir, 'remotes', 'repo_clean.git') }
      let(:local_repo_path) { File.join(@work_dir, 'repo_clean') }
      let(:new_remote_file) { File.join(local_repo_path, 'new_remote_file.txt') }

      before do
        # Add a new commit to the bare "remote" repo
        clone_path = File.join(@tmpdir, 'clone_for_commit')
        git("clone #{remote_path} #{clone_path}")
        File.write(File.join(clone_path, 'new_remote_file.txt'), 'remote change')
        git('add .', clone_path)
        git('commit -m "Remote commit"', clone_path)
        git('push origin main', clone_path)
        FileUtils.rm_rf(clone_path)
      end

      it 'successfully runs git-update' do
        result = run_command("git-update '#{@work_dir}'")
        expect(result).to be_successful
        expect(result[:stderr]).to be_empty
      end

      it 'pulls the new file into the local repository' do
        run_command("git-update '#{@work_dir}'")
        expect(File.exist?(new_remote_file)).to be true
      end
    end

    it 'handles an undefined environment variable gracefully' do
      result = run_command("git-update '$UNDEFINED_VAR'")
      expect(result[:status].exitstatus).to eq(1)
      expect(result[:stderr]).to include("Environment variable '$UNDEFINED_VAR' is undefined.")
    end
  end

  describe 'git-replicate' do
    context 'when generating a replication script' do
      it 'succeeds and generates a non-empty script' do
        result = run_command("git-replicate '$WORK'")
        expect(result).to be_successful
        expect(result[:stdout]).not_to be_empty
      end

      it 'generates a script that can successfully clone the repositories' do
        result = run_command("git-replicate '$WORK'")
        replication_script = result[:stdout]

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

    it 'handles an undefined environment variable gracefully' do
      result = run_command("git-replicate '$UNDEFINED_VAR'")
      expect(result[:status].exitstatus).to eq(1)
      expect(result[:stderr]).to include("Environment variable '$UNDEFINED_VAR' is undefined.")
    end
  end

  describe 'git-evars' do
    context 'when generating evars for a specific root' do
      it 'succeeds' do
        result = run_command("git-evars '$WORK'")
        expect(result).to be_successful
      end

      it 'generates correct export statements' do
        result = run_command("git-evars '$WORK'")
        expect(result[:stdout]).to include("export repo_clean=$WORK/repo_clean", "export repo_modified=$WORK/repo_modified")
      end
    end

    it 'handles undefined environment variables gracefully' do
      result = run_command("git-evars '$UNDEFINED_VAR'")
      expect(result[:status].exitstatus).to eq(1)
      expect(result[:stderr]).to include("Environment variable '$UNDEFINED_VAR' is undefined.")
    end
  end

  describe 'git-commitAll' do
    context 'when committing changes' do
      before do
        # This command modifies the state of the repos, so we run it once
        # and then test the side effects in separate examples.
        @result = run_command('git-commitAll -m "Test commit"')
      end

      it 'succeeds' do
        expect(@result).to be_successful
      end

      it 'commits modified files' do
        log_output = `git -C #{@repo_modified_path} log -1 --pretty=%B 2> /dev/null`.strip
        expect(log_output).to eq("Test commit")
      end

      it 'commits new files' do
        log_output = `git -C #{@repo_new_file_path} log -1 --pretty=%B 2> /dev/null`.strip
        expect(log_output).to eq("Test commit")
      end

      it 'commits deleted files' do
        log_output = `git -C #{@repo_deleted_file_path} log -1 --pretty=%B 2> /dev/null`.strip
        expect(log_output).to eq("Test commit")
      end
    end

    context 'when a repository has a detached HEAD' do
      it 'succeeds' do
        # The command should still succeed overall even if it skips one repo.
        result = run_command('git-commitAll -v -m "Test commit"')
        expect(result).to be_successful
      end

      it 'logs a skip message to stderr' do
        result = run_command('git-commitAll -v -m "Test commit"') # Use -v to get log output
        expect(result[:stderr]).to include("Skipping #{@repo_detached_path} because it is in a detached HEAD state")
      end
    end

    it 'handles an undefined environment variable gracefully' do
      result = run_command("git-commitAll '$UNDEFINED_VAR'")
      expect(result[:status].exitstatus).to eq(1)
      expect(result[:stderr]).to include("Environment variable '$UNDEFINED_VAR' is undefined.")
    end
  end
end

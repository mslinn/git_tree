require 'spec_helper'
require 'tmpdir'
require 'fileutils'
require 'open3'

RSpec.describe 'Command-line Integration' do # rubocop:disable RSpec/DescribeClass
  # This spec tests the end-to-end functionality of the command-line executables.
  # It creates a real file system structure with git repositories and runs the
  # commands as a user would, capturing their output and verifying side effects.

  # --- Helper to run commands ---
  def run_command(command_string)
    # Point to the executables in the `exe` directory
    exe_path = File.expand_path('../../exe', __dir__)
    env = {
      'HOME'  => @home_dir,
      'WORK'  => @work_dir,
      'SITES' => @sites_dir,
      'PATH'  => "#{exe_path}:#{ENV.fetch('PATH', nil)}",
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
    # as the `path` can be an absolute path.
    Dir.chdir(@tmpdir) { git("clone #{bare_repo_path} #{path}") }

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
    setup_repo(File.join(@work_dir, 'repo_clean'), 'repo_clean')

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
    head_commit_sha = `git -C #{@repo_detached_path} rev-parse HEAD`.strip
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
    it 'runs a command on all non-ignored repos' do
      result = run_command("git-exec pwd")
      expect(result[:status]).to be_success
      expect(result[:stdout].lines.count).to eq(@all_processable_repos.count)
      expect(result[:stdout]).to include(@repo_modified_path)
      expect(result[:stdout]).not_to include(@repo_ignored_path)
    end

    it 'handles an invalid command' do
      result = run_command("git-exec nonexistentcommand")
      expect(result[:status]).to be_success # The tool itself succeeds
      expect(result[:stderr]).to include("Error: Command 'nonexistentcommand' not found")
    end

    it 'respects the -q flag' do
      # Create a config with high verbosity
      File.write(File.join(@home_dir, '.treeconfig.yml'), "verbosity: 2")
      result = run_command("git-exec -q pwd")
      expect(result[:stderr]).to be_empty
    end

    it 'runs a command only on an explicitly specified root' do
      # This test ensures that providing a root on the command line overrides the defaults.
      # We expect it to find the 4 repos in @work_dir and not the one in @sites_dir.
      result = run_command("git-exec '#{@work_dir}' pwd")
      expect(result[:status]).to be_success
      expect(result[:stdout].lines.count).to eq(@processable_work_repos.count)
      expect(result[:stdout]).not_to include(@repo_detached_path) # This repo is in @sites_dir
    end

    it 'handles an undefined environment variable gracefully' do
      result = run_command("git-exec '$UNDEFINED_VAR' pwd")
      expect(result[:status].exitstatus).to eq(1)
      expect(result[:stderr]).to include("Environment variable '$UNDEFINED_VAR' is undefined.")
    end
  end

  describe 'git-commitAll' do
    it 'commits modified, new, and deleted files' do
      result = run_command('git-commitAll -m "Test commit"')
      expect(result[:status]).to be_success

      # Verify repo_modified was committed
      log_output_modified = `git -C #{@repo_modified_path} log -1 --pretty=%B`.strip
      expect(log_output_modified).to eq("Test commit")

      # Verify repo_new_file was committed
      log_output_new = `git -C #{@repo_new_file_path} log -1 --pretty=%B`.strip
      expect(log_output_new).to eq("Test commit")

      # Verify repo_deleted_file was committed
      log_output_deleted = `git -C #{@repo_deleted_file_path} log -1 --pretty=%B`.strip
      expect(log_output_deleted).to eq("Test commit")
    end

    it 'skips detached HEAD repos' do
      result = run_command('git-commitAll -v -m "Test commit"') # Use -v to get log output
      expect(result[:stderr]).to include("Skipping #{@repo_detached_path} because it is in a detached HEAD state")
    end

    it 'handles an undefined environment variable gracefully' do
      result = run_command("git-commitAll '$UNDEFINED_VAR'")
      expect(result[:status].exitstatus).to eq(1)
      expect(result[:stderr]).to include("Environment variable '$UNDEFINED_VAR' is undefined.")
    end
  end

  describe 'git-update' do
    it 'pulls changes from the remote' do
      # Add a new commit to the bare "remote" repo
      remote_path = File.join(@tmpdir, 'remotes', 'repo_clean.git')
      clone_path = File.join(@tmpdir, 'clone_for_commit')
      git("clone #{remote_path} #{clone_path}")
      File.write(File.join(clone_path, 'new_remote_file.txt'), 'remote change')
      git('add .', clone_path)
      git('commit -m "Remote commit"', clone_path)
      git('push origin main', clone_path)
      FileUtils.rm_rf(clone_path)

      # Run git-update
      result = run_command("git-update '$WORK/repo_clean'")
      expect(result[:status]).to be_success

      # Verify the local repo now has the remote file
      expect(File.exist?(File.join(@work_dir, 'repo_clean', 'new_remote_file.txt'))).to be true
    end

    it 'handles an undefined environment variable gracefully' do
      result = run_command("git-update '$UNDEFINED_VAR'")
      expect(result[:status].exitstatus).to eq(1)
      expect(result[:stderr]).to include("Environment variable '$UNDEFINED_VAR' is undefined.")
    end
  end

  describe 'git-replicate' do
    it 'generates a script that successfully clones repositories' do
      result = run_command("git-replicate '$WORK'")
      expect(result[:status]).to be_success

      replication_script = result[:stdout]

      # Run the generated script in a new temp directory
      replication_dir = Dir.mktmpdir('replication_target')
      File.write(File.join(replication_dir, 'replicate.sh'), replication_script)
      system("bash", File.join(replication_dir, 'replicate.sh'))

      # Verify that the repos were cloned
      expect(Dir.exist?(File.join(replication_dir, 'repo_clean',        '.git'))).to be true
      expect(Dir.exist?(File.join(replication_dir, 'repo_modified',     '.git'))).to be true
      expect(Dir.exist?(File.join(replication_dir, 'repo_new_file',     '.git'))).to be true
      expect(Dir.exist?(File.join(replication_dir, 'repo_deleted_file', '.git'))).to be true

      FileUtils.remove_entry(replication_dir)
    end

    it 'handles an undefined environment variable gracefully' do
      result = run_command("git-replicate '$UNDEFINED_VAR'")
      expect(result[:status].exitstatus).to eq(1)
      expect(result[:stderr]).to include("Environment variable '$UNDEFINED_VAR' is undefined.")
    end
  end

  describe 'git-evars' do
    it 'generates environment variables for found repos' do
      result = run_command("git-evars '$WORK'")
      expect(result[:status]).to be_success
      expect(result[:stdout]).to include("export repo_clean=$WORK/repo_clean")
      expect(result[:stdout]).to include("export repo_modified=$WORK/repo_modified")
    end

    it 'handles undefined environment variables gracefully' do
      result = run_command("git-evars '$UNDEFINED_VAR'")
      expect(result[:status].exitstatus).to eq(1)
      expect(result[:stderr]).to include("Environment variable '$UNDEFINED_VAR' is undefined.")
    end
  end
end

`Replicate_git_tree`
[![Gem Version](https://badge.fury.io/rb/replicate_git_tree.svg)](https://badge.fury.io/rb/replicate_git_tree)
===========

`Replicate_git_tree` scans a git directory tree and writes out a script that clones the repos in the tree.

 - All remotes are replicated.
 - Subdirectory trees containing a file called `.ignore` are ignored.
 - Any git repos that have already been cloned into the target directory tree are skipped.
   This means you can rerun `replicate_git_tree` as many times as you want, without ill effects.


## Usage
The program requires only one parameter:
the name of the top-level directory to replicate.

The following creates a script in the current directory called `work.sh`,
that replicates the desired portions of the directory tree of git repos under `top_level`:
```shell
$ replicate_git_tree top_level > work.sh
```

When `replicate_git_tree` completes,
copy the generated script to the target machine and run it.
The following example copies the script to `machine2` and runs it:
```shell
$ scp work.sh machine2:

$ ssh machine2 bash work.sh
```


## Installation
Type the following at a shell prompt:

```ruby
$ gem install replicate_git_tree
```


## Additional Information
More information is available on
[Mike Slinn&rsquo;s website](https://www.mslinn.com/git/1100-git-tree.html)


## Development
After checking out the repo, run `bin/setup` to install dependencies.

Run `bin/make_test_directory` to create a directory tree for testing.

You can also run `bin/console` for an interactive prompt that will allow you to experiment.
```
$ bin/console
irb(main):001:0> ReplicateGitTree.run 'demo'
```


### Build and Install Locally
To build and install this gem onto your local machine, run:
```shell
$ bundle exec rake install
```

Examine the newly built gem:
```
$ gem info replicate_git_tree

*** LOCAL GEMS ***
replicate_git_tree (0.1.0)
    Author: Mike Slinn
    Homepage:
    https://github.com/mslinn/replicate_git_tree
    License: MIT
    Installed at: /home/mslinn/.gems
```


### Build and Push to RubyGems
To release a new version,
  1. Update the version number in `version.rb`.
  2. Commit all changes to git; if you don't the next step might fail with an unexplainable error message.
  3. Run the following:
     ```shell
     $ bundle exec rake release
     ```
     The above creates a git tag for the version, commits the created tag,
     and pushes the new `.gem` file to [RubyGems.org](https://rubygems.org).


## Contributing

1. Fork the project
2. Create a descriptively named feature branch
3. Add your feature
4. Submit a pull request


## License
The gem is available as open source under the terms of the [MIT License](https://opensource.org/licenses/MIT).

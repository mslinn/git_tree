`Git_tree`
[![Gem Version](https://badge.fury.io/rb/git_tree.svg)](https://badge.fury.io/rb/git_tree)
===========

This Ruby gem installs two commands that scan a git directory tree and write out scripts.
Directories containing a file called `.ignore` are ignored.

 - The `git_tree_replicate` command writes a script that clones the repos in the tree,
   and adds any defined remotes.
   - Any git repos that have already been cloned into the target directory tree are skipped.
     This means you can rerun `git_tree_replicate` as many times as you want, without ill effects.
   - All remotes in each repo are replicated.

 - The `git_tree_evars` command writes a script that defines environment variables pointing to git repos.


## Usage
Both commands requires only one parameter:
the name of the top-level directory to scan.

You must pass an environment variable to both commands.
Enclosing the name of the env var in single quotes,
which will prevent the shell from expanding it before invoking either command.


## `Git_tree_replicate` Usage
The following creates a script in the current directory called `work.sh`,
that replicates the desired portions of the directory tree of git repos pointed to by `$work`:
```shell
$ git_tree_replicate '$work' > work.sh
```

The generated environment variables will all be relative to the
env var you provided.
You will understand what this means once you try it and look at the generated script.

When `git_tree_replicate` completes,
edit the generated script to suit, then
copy it to the target machine and run it.
The following example copies the script to `machine2` and runs it:

```shell
$ scp work.sh machine2:

$ ssh machine2 work.sh
```


### Generated Script from `git_tree_replicate`
Following is a sample of one section, which is repeated for every git repo that is processed:
You can edit them to suit.

```shell
if [ ! -d "sinatra/sinatras-skeleton/.git" ]; then
  mkdir -p 'sinatra'
  pushd 'sinatra' > /dev/null
  git clone git@github.com:mslinn/sinatras-skeleton.git
  git remote add upstream 'https://github.com/simonneutert/sinatras-skeleton.git'
  popd > /dev/null
fi
```

## `Git_tree_evars` Usage
The `git_tree_evars` command should be run on the target computer.
The command requires only one parameter:
an environment variable reference, pointing to the top-level directory to replicate.
The environment variable reference must be contained within single quotes to prevent expansion by the shell.

The following appends to any script in the `$work` directory called `.evars`.
The script defines environment variables that point to each git repos pointed to by `$work`:
```shell
$ git_tree_evars '$work' >> $work/.evars
```


### Generated Script from `git_tree_evars`
Following is a sample of environment variable definitions.
You can edit it to suit.

```shell
export work=/mnt/c/work
export ancientWarmth=$work/ancientWarmth/ancientWarmth
export ancientWarmthBackend=$work/ancientWarmth/ancientWarmthBackend
export braintreeTutorial=$work/ancientWarmth/braintreeTutorial
export survey_analytics=$work/ancientWarmth/survey-analytics
export survey_creator=$work/ancientWarmth/survey-creator
export django=$work/django/django
export frobshop=$work/django/frobshop
```

The environment variable definitions are meant to be saved into a file that is `source`d upon boot.
While you could place them in a file like `~/.bashrc`,
the author's preference is to instead place them in `$work/.evars`,
and add the following to `~/.bashrc`:
```shell
source "$work/.evars"
```

Thus each time you log in, the environment variable definitions will have been re-established.
You can therefore change directory to any of the cloned projects, like this:
```shell
$ cd $git_root

$ cd $my_project
```


## Installation
Type the following at a shell prompt:

```shell
$ gem install git_tree
```


## Additional Information
More information is available on
[Mike Slinn&rsquo;s website](https://www.mslinn.com/git/1100-git-tree.html)


## Development
After checking out the repo, run `bin/setup` to install dependencies.

Run the following to create a directory tree for testing.
```shell
$ ruby bin/make_test_directory.rb
```

You can run `bin/console` for an interactive prompt that will allow you to experiment.
```
$ bin/console
irb(main):001:0> GitTree.command_replicate 'demo'

irb(main):002:0> GitTree.command_evars 'demo'
```


### Build and Install Locally
To build and install this gem onto your local machine, run:
```shell
$ bundle exec rake install
```

Examine the newly built gem:
```
$ gem info git_tree

*** LOCAL GEMS ***
git_tree (0.2.0)
    Author: Mike Slinn
    Homepage:
    https://github.com/mslinn/git_tree_replicate
    License: MIT
    Installed at: /home/mslinn/.gems
```


### Build and Push to RubyGems
To release a new version,
  1. Update the version number in `version.rb`.
  2. Commit all changes to git; if you don't the next step might fail with an
     unexplainable error message.
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

# `Git_tree` [![Gem Version](https://badge.fury.io/rb/git_tree.svg)](https://badge.fury.io/rb/git_tree)

This Ruby gem installs 3 commands that scan a git directory tree;
2 of the commands write out scripts and the third executes an arbitrary bash command for each repository.
Directories containing a file called `.ignore` are ignored.

- The `git-tree-replicate` command writes a script that clones the repos in the tree,
  and adds any defined remotes.
  - Any git repos that have already been cloned into the target directory tree are skipped.
    This means you can rerun `git-tree-replicate` as many times as you want, without ill effects.
  - All remotes in each repo are replicated.

- The `git-tree-evars` command writes a script that defines environment variables pointing to git repos.

- The `git-tree-exec` command executes an arbitrary bash command for each repository.


## Usage

All commands require one environment variable reference to be passed to them.
Enclose the name of the environment variable within single quotes,
which will prevent the shell from expanding it before invoking the command.


## `git-tree-replicate` Usage

The following creates a script in the current directory called `work.sh`,
that replicates the desired portions of the directory tree of git repos pointed to by `$work`:

```shell
$ git-tree-replicate '$work' > work.sh
```

The generated environment variables will all be relative to the
path pointed to by the expanded environment variable that you provided.
You will understand what this means once you look at the generated script.

When `git-tree-replicate` completes,
edit the generated script to suit, then
copy it to the target machine and run it.
The following example copies the script to `machine2` and runs it:

```shell
$ scp work.sh machine2:

$ ssh machine2 work.sh
```


### Generated Script from `git-tree-replicate`

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

## `git-tree-evars` Usage

The `git-tree-evars` command should be run on the target computer.
The command requires only one parameter:
an environment variable reference, pointing to the top-level directory to replicate.
The environment variable reference must be contained within single quotes to prevent expansion by the shell.

The following appends to any script in the `$work` directory called `.evars`.
The script defines environment variables that point to each git repos pointed to by `$work`:

```shell
$ git-tree-evars '$work' >> $work/.evars
```


### Generated Script from `git-tree-evars`

Following is a sample of environment variable definitions.
You are expected to edit it to suit.

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


## `git-tree-exec` Usage

The `git-tree-exec` command can be run on any computer.
The command requires two parameters.
The first parameter indicates the directory or directories to process.
3 forms are accepted:

  1. A directory name, which may be relative or absolute.
  2. An environment variable reference,
     which must be contained within single quotes to prevent expansion by the shell.
  3. A list of directory names, which may be relative or absolute, and may contain environment variables.

### Example 1

For all subdirectories of current directory,
update `Gemfile.lock` and install a local copy of the gem:

```shell
$ git-tree-exec '
  $jekyll_plugin_logger
  $jekyll_draft
  $jekyll_plugin_support
  $jekyll_all_collections
  $jekyll_plugin_template
  $jekyll_flexible_include_plugin
  $jekyll_href
  $jekyll_img
  $jekyll_outline
  $jekyll_plugin_template
  $jekyll_pre
  $jekyll_quote
' 'bundle && bundle update && rake install'
```

### Example 2

This example shows how to display the version of projects that
create gems under the directory pointed to by `$my_plugins`.

An executable script is required on the `PATH`, so `git-tree-exec`
can invoke it as it loops through the subdirectories.
I call this script `version`, and it is written in `bash`,
although the language used is not significant:

```shell
#!/bin/bash

x="$( ls lib/**/version.rb 2> /dev/null )"
if [ -f "$x" ]; then
  v="$(
    cat "$x" | \
    grep '=' | \
    sed -e s/.freeze// | \
    tr -d 'VERSION =\"' | \
    tr -d \'
  )"
  echo "$(basename $PWD) v$v"
fi
```

Call it like this:

```shell
$ git-tree-exec '$my_plugins' version
jekyll_all_collections v0.3.3
jekyll_archive_create v1.0.2
jekyll_archive_display v1.0.1
jekyll_auto_redirect v0.1.0
jekyll_basename_dirname v1.0.3
jekyll_begin_end v1.0.1
jekyll_bootstrap5_tabs v1.1.2
jekyll_context_inspector v1.0.1
jekyll_download_link v1.0.1
jekyll_draft v1.1.2
jekyll_flexible_include_plugin v2.0.20
jekyll_from_to_until v1.0.3
jekyll_href v1.2.5
jekyll_img v0.1.5
jekyll_nth v1.1.0
jekyll_outline v1.2.0
jekyll_pdf v0.1.0
jekyll_plugin_logger v2.1.1
jekyll_plugin_support v0.7.0
jekyll_plugin_template v0.3.0
jekyll_pre v1.4.1
jekyll_quote v0.4.0
jekyll_random_hex v1.0.0
jekyll_reading_time v1.0.0
jekyll_revision v0.1.0
jekyll_run v1.0.1
jekyll_site_inspector v1.0.0
jekyll_sort_natural v1.0.0
jekyll_time_since v0.1.3
```

### Example 3

List the projects under the directory pointed to by `$my_plugins`
that have a `demo/` subdirectory:

```shell
$ git-tree-exec '$my_plugins' \
  'if [ -d demo ]; then realpath demo; fi'
/mnt/c/work/jekyll/my_plugins/jekyll-hello/demo
/mnt/c/work/jekyll/my_plugins/jekyll_all_collections/demo
/mnt/c/work/jekyll/my_plugins/jekyll_archive_create/demo
/mnt/c/work/jekyll/my_plugins/jekyll_download_link/demo
/mnt/c/work/jekyll/my_plugins/jekyll_draft/demo
/mnt/c/work/jekyll/my_plugins/jekyll_flexible_include_plugin/demo
/mnt/c/work/jekyll/my_plugins/jekyll_from_to_until/demo
/mnt/c/work/jekyll/my_plugins/jekyll_href/demo
/mnt/c/work/jekyll/my_plugins/jekyll_img/demo
/mnt/c/work/jekyll/my_plugins/jekyll_outline/demo
/mnt/c/work/jekyll/my_plugins/jekyll_pdf/demo
/mnt/c/work/jekyll/my_plugins/jekyll_plugin_support/demo
/mnt/c/work/jekyll/my_plugins/jekyll_plugin_template/demo
/mnt/c/work/jekyll/my_plugins/jekyll_pre/demo
/mnt/c/work/jekyll/my_plugins/jekyll_quote/demo
/mnt/c/work/jekyll/my_plugins/jekyll_revision/demo
/mnt/c/work/jekyll/my_plugins/jekyll_time_since/demo
```


## Installation

Type the following at a shell prompt on the machine you are copying the git tree from,
and on the machine that you are copying the git tree to:

```shell
$ yes | sudo apt install cmake libgit2-dev libssh2-1-dev pkg-config

$ gem install git_tree
```

To register the new commands, either log out and log back in, or open a new console.


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

```shell
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

```shell
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

To release a new version:

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

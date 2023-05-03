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

If you want to pass an environment variable to `replicate_git_tree`, enclose it in single quotes, which will prevent the shell from expanding it before invoking `replicate_git_tree`:
```shell
$ replicate_git_tree '$work' > work.sh
```
The benefit of doing that is that the generated environment variables will all be relative to the env var you provided.
You will understand what this means once you try it and look at the generated script.

When `replicate_git_tree` completes,
edit the generated script to suit, then
copy it to the target machine and run it.
The following example copies the script to `machine2` and runs it:
```shell
$ scp work.sh machine2:

$ ssh machine2 work.sh
```

### Generated Script
The generated script has 2 parts:

 1. Git repo cloning.
 2. Environment variable definitions, one for each cloned git repo.

Following is a sample of a git clone:

```shell
if [ ! -d "sinatra/sinatras-skeleton/.git" ]; then
  mkdir -p 'sinatra'
  pushd 'sinatra' > /dev/null
  git clone git@github.com:mslinn/sinatras-skeleton.git
  git remote add upstream 'https://github.com/simonneutert/sinatras-skeleton.git'
  popd > /dev/null
fi
```

Following is a sample of environment variable definitions.
Please edit it to suit.
Notice that it appends these environment variable definitions to `$work/.evars`.
You could cause it to replace the contents of that file by changing the `>>` to `>`.
```shell
cat <<EOF >> $work/.evars
export work=/mnt/c/work
export ancientWarmth=$work/ancientWarmth/ancientWarmth
export ancientWarmthBackend=$work/ancientWarmth/ancientWarmthBackend
export braintreeTutorial=$work/ancientWarmth/braintreeTutorial
export survey_analytics=$work/ancientWarmth/survey-analytics
export survey_creator=$work/ancientWarmth/survey-creator
export django=$work/django/django
export frobshop=$work/django/frobshop
EOF
```

The environment variable definitions are meant to be saved into a file that is `source`d upon boot.
While you could place them in a file like `~/.bashrc`, the author's preference is to instead place them in `$work/.evars`, and add the following to `~/.bashrc`:
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
irb(main):001:0> GitTree.run 'demo'
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

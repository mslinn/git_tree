# Change Log

## 1.0.2 / 2025-10-04

* Increased `GitTreeWalker.GIT_TIMEOUT` to 5 minutes.
* Added `git-treeconfig` command and support for configuration file and environment variable configuration.


## 1.0.1 / 2025-10-04

* Removed unnecessary and problematic `gem_support` dependency.


## 1.0.0 / 2025-10-04

* Made the file search breadth-first instead of depth-first,
  greatly increasing performance.
* Added `git-update` and `git-commitAll` commands.
* Renamed `git-tree-replicate`, `git-tree-evars` and `git-tree-exec` to
  `git-replicate`, `git-evars` and `git-exec`.
* Added spec.platform to `.gemspec` because `RubyGems.org` now requires it.


## 0.3.0 / 2023-06-01

* Added `git-tree-exec` command.


## 0.2.3 / 2023-05-26

* Improved help messages.
* Renamed executables to `git-tree-replicate` and `git-tree-evars`.


## 0.2.2 / 2023-05-23

* `git_tree_evars` now checks for previous definitions and issues warnings.


## 0.2.1 / 2023-05-03

* Removed the here document wrapper from the output of `git_tree_evars`.


## 0.2.0 / 2023-05-03

* Renamed gem to `git_tree`
* Renamed `replicate_git_tree` command to `git_tree_replicate`.
* Added `.evars` support with new executable: `git_tree_evars`
* Added support for a symlinked root directory


## 0.1.3 / 2023-05-01

* Fussing with directory path (works!!!)


## 0.1.2 / 2023-05-01

* Fussing with gem executable (did not work)


## 0.1.1 / 2023-05-01

* Added missing file (did not work)


## 0.1.0 / 2023-05-01

* Published as a gem (did not work)


## 2021-04-10

* Initial version published at https://www.mslinn.com/git/1100-git-tree.html

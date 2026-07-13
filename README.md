# t

[![Ask DeepWiki](https://deepwiki.com/badge.svg)](https://deepwiki.com/crisfeim/t)
[![CI](https://github.com/crisfeim/t/actions/workflows/ci.yml/badge.svg)](https://github.com/crisfeim/t/actions/workflows/ci.yml)

A minimalist CLI todo manager written in Ocaml, inspired by [Steve Losh's `t`](https://github.com/sjl/t), but built with explicit support for Git & Fossil commits, global project management, and sequential line-based IDs.

> ! This is a mirror of a fossil repo. Original code lives in https://chiselapp.com/user/crisfeim/repository/t/timeline

## Usage

```bash
t          # List todos in local .todo
t "Some"   # Adds a todo with "Some" contents in last line of local .todo
t 1        # Echoes todo in line 1
t 1...5    # Echoes todos from 1 to 5
t :        # Opens $EDITOR for editing the local .todo file
t :1       # Opens $EDITOR for editing todo in line 1
t :1 "New" # Updates content of todo in line 1
t +1       # Completes todo in line 1 & archives it in local .done
t -1       # Removes todo in line 1
t c1       # If fossil/git, commits all changes using line 1's content as message
t c:1      # Opens editor before committing contents of line 1
t @1       # Toggles @doing tag in todo 1
t @        # Shows all todos tagged as @doing in local .todo
t .        # Shows all folders holding a .todo file within user's folder
t .@       # Shows all todos tagged as @doing across every project folder
t .<folder-name>        # Shows todos in folder-name/.todo. Name is matched using a disambiguation algorithm based on folders containing a .todo file.
t .<folder-name> <text> # Adds a new todo to folder-name/.todo
t .<folder-name> (1...5|:1|+1|-1|c1|c:1|@) # Executes any of the above commands in the scope of <folder-name>
```

## Requirements

- macOS / Linux
- `find`, `vi`
- Git or Fossil (optional, for VCS tracking)

## Installation

Use make to compile & copy to `~/.local/bin`.

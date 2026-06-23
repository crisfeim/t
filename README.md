# t

A minimalist CLI todo manager written in Swift, inspired by [Steve Losh's `t`](https://github.com/sjl/t), but built with explicit support for direct Version Control System (Git/Fossil) commits and sequential line-based IDs.

## Rationale

Unlike the original `t` which uses unique alphanumeric hashes for task identification, this implementation uses the raw file line number as the ID. 

* Ergonomics: It keeps commands short ("t complete 1") and matches the visual layout exactly.
* Interoperability: Because tasks are just lines in a plaintext file, you can open `.todo` in any standard editor (or TaskPaper) to reorder, add, or delete lines manually without breaking external IDs.
* Integrated Workflow: It allows you to complete and commit a task to your repository in a single atomic operation ("t commit 1"), avoiding context switching.

## Requirements

* macOS / Linux
* find, vi
* Git or Fossil (optional, for VCS tracking)

## Installation

Use make to compile & move to `./local/bin`.

## Usage

Data persists locally in `.todo` and `.done` files relative to the current directory.

* List pending tasks:
```bash
t list
```

* Add a new task:
```bash
t add "Buy milk"
```

* Complete a task (moves it to `.done` with a timestamp prefix):
```bash
t complete 1
```

* Edit a task (opens the line inside `vi`):
```bash
t edit 1
```

* Remove a task (hard deletion without archiving to `.done`):
```bash
t remove 1
```

* Locate all todo files in the home directory system:
```bash
t all
```

* List tasks from a specific project file:
```bash
t project <name>
```

* Complete and commit via VCS:
```bash
t commit 1
t commit editor 1
```

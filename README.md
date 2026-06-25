# t

[![Ask DeepWiki](https://deepwiki.com/badge.svg)](https://deepwiki.com/crisfeim/t)
[![CI](https://github.com/crisfeim/t/actions/workflows/ci.yml/badge.svg)](https://github.com/crisfeim/t/actions/workflows/ci.yml)

A minimalist CLI todo manager written in Swift, inspired by [Steve Losh's `t`](https://github.com/sjl/t), but built with explicit support for direct Version Control System (Git/Fossil) commits, global project multi-scoping, and sequential line-based IDs.

> ! This is a mirror of a fossil repo. Original code lives in https://chiselapp.com/user/crisfeim/repository/t/timeline

## Rationale

Unlike the original `t` which uses unique alphanumeric hashes for todo identification, this implementation uses the raw file line number as the ID. 

* **Interoperability:** Because todos are just lines in a plaintext file, opening `.todo` in any standard editor (ex.: TaskPaper) allows reordering, adding, or deleting lines manually without breaking external IDs.
* **Integrated Workflow:** The completion and commitment of a todo to the repository occurs in a single operation (`t commit 1`), avoiding context switching.

## Requirements

* macOS / Linux
* `find`, `vi`
* Git or Fossil (optional, for VCS tracking)

## Installation

Use make to compile & move to `~/.local/bin`.

## Usage

By default, data persists locally in `.todo` and `.done` files relative to the current working directory. Targeting specific external projects from any location is possible using the `project` modifier.

### Basic Commands

Commands have no short form for now.

* **List pending todos:**
```bash
t list
```

* **Add a new todo:**
```bash
t add "Buy milk"
```

* **Complete a todo** (moves the task to `.done` with a `yyyyMMddHHmmss` timestamp prefix):
```bash
t complete 1
```

* **Edit a todo** (opens the specific line inside `vi`):
```bash
t edit 1
```

* **Remove todos** (supports bulk hard deletion without archiving to `.done`):
```bash
t remove 1 2 3
```

* **Copy a todo content** directly to the system clipboard:
```bash
t copy 1
```

---

### Global Project Management

Querying or manipulating `.todo` files across the entire home directory is supported using the folder name of the project. The tool resolves paths by matching exact directory names, filtering out false positives (like sub-strings in `dotfiles`).

* **List all `.todo` paths discovered in the system:**
```bash
t all
```

* **Inspect all projects and respective lines simultaneously:**
```bash
t projects
```

* **Scope any command to a specific project directory:**
```bash
t project <project_dir_name> list
t project <project_dir_name> add "Fix compiler warning"
t project <project_dir_name> remove 3 2 1
```
*(If no command is provided, execution defaults to `list`)*
*(When multiple `.todo` files match a project name, the tool picks the one whose containing folder is closest to the roo)*
---

### Integrated Version Control (VCS)

The tool walks up the directory tree starting from the parent folder of the active `.todo` file to detect a repository, ensuring operations work when executed via the global `project` router.

* **Complete and commit using the task content as the message:**
```bash
t commit 1
```

* **Complete and edit the commit message before submitting** (opens `vi` with the task text):
```bash
t commit editor 1
```

*Supports both Git (`git add -A && commit`) and Fossil (`fossil addremove && commit`) automatically based on repository detection.*

# Tasks-specific test drivers, layered over the generic ../test harness.
# This file is the extraction seam: everything here knows about the tasks
# module; nothing in ../test does.
const NU_LIB_DIRS = [
  ($nu.data-dir | path basename --replace nupm | path join modules)
]
export use std/assert
export use test *

const MODULE: path = path self ..
const FIXTURES: path = path self ./fixtures

# Run nu code in a sandbox-scoped child with the tasks module imported.
export def tasks-run [ctx: record code: string]: nothing -> record {
  sandboxed $ctx $code --prelude $"use ($MODULE | to nuon)"
}

# Assert a child succeeded and hand back its trimmed stdout.
export def unwrap []: record -> string {
  let out = $in
  if $out.exit_code != 0 {
    error make --unspanned $"child failed:\n($out.stderr)"
  }
  $out.stdout | str trim
}

# Stage the fixture project into a sandbox: docs/, tombi config, schema
# snapshot, and the TOML issue file (with an issue.reference block when
# --reference names a branch). Returns the project's paths.
export def stage-project [
  ctx: record
  --reference: string = '' # Declare this branch in $.issue.reference
]: nothing -> record<root: path, docs: path, file: path, json: path> {
  let root: path = $ctx.code | path join proj-a
  let docs: path = $root | path join docs
  mkdir $docs
  cp ($FIXTURES | path join issue.schema.json) ($docs | path join issue.schema.json)
  cp ($FIXTURES | path join tombi.toml) ($root | path join .tombi.toml)
  cp ($FIXTURES | path join other.issue.json) ($docs | path join other.issue.json)
  open --raw ($FIXTURES | path join thing.issue.toml)
  | str replace '# %reference%' (
    match $reference {
      '' => ''
      $b => (
        [
          "[issue.reference]"
          "    index  = 1"
          $"    branch = '($b)'"
          "    url    = 'https://example.com/1'"
        ] | str join "\n  "
      )
    }
  )
  | save --force --raw ($docs | path join thing.issue.toml)
  {
    root: $root
    docs: $docs
    file: ($docs | path join thing.issue.toml)
    json: ($docs | path join other.issue.json)
  }
}

# Turn a staged project into a git repository on main, with repo-local
# identity (children run with HOME inside the sandbox) and optional extra
# branches at the initial commit.
export def git-init [root: path --branches: list<string> = []]: nothing -> nothing {
  git -C $root init --quiet --initial-branch main
  git -C $root config user.name tester
  git -C $root config user.email tester@test
  git -C $root add --all
  git -C $root commit --quiet --message initial
  for b in $branches { git -C $root branch $b }
}

# The document lines preceding the first tasks-scoped header: the region a
# sync splice must never touch.
export def head-lines [file: path]: nothing -> list<string> {
  open --raw $file | lines | take until {|l| $l =~ '^\s*\[tasks' }
}

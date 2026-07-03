#!/usr/bin/env -S nu --stdin

const ROOT: path = path self ..
const REQUIREMENTS: path = path self ../docs/requirements.txt
const REGEX: string = '^\s*(?P<name>[A-Za-z0-9_.-]+)\s*(?:(?P<min_op>[><=]=|>)\s*(?P<min_version>[0-9]+(?:\.[0-9]+){0,2}(?:-[A-Za-z0-9_.-]+)?))?'

def main []: nothing -> nothing {
  if (which git | is-empty) { error make --unspanned 'ensure git is installed and on PATH' }

  try { git -C $ROOT config core.hooksPath .githooks } catch {
    error make 'unable to update git config with hooks path'
  }

  if (which pipx | is-empty) { error make --unspanned 'ensure pipx is installed and on PATH' }

  let reqs: list<string> = open $REQUIREMENTS
    | lines | str trim | compact --empty | where $it !~ ^# | uniq
  let spec: string = $reqs | first
  let deps: list = $reqs | skip 1
  let main: record<name: string> = $spec | parse --regex $REGEX | first

  if (which $main.name | is-empty) or (^$main.name --version) !~ $main.min_version {
    try { pipx install --force $spec } catch {
      error make $'($main.name) installation did not succeed'
    }
  }

  if ($deps | is-not-empty) {
    try { pipx inject --force $main.name ...$deps } catch {
      error make 'dependency injection did not succeed'
    }
  }
}

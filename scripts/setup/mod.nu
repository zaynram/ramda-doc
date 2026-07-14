use std/log

const ROOT: path = path self ../..
const REQUIREMENTS: path = $ROOT | path join docs requirements.txt
const REGEX: string = '^\s*(?P<name>[A-Za-z0-9_.-]+)\s*(?:(?P<sep>[><=]=|>)\s*(?P<version>[0-9]+(?:\.[0-9]+){0,2}(?:-[A-Za-z0-9_.-]+)?))?'
const D2: record<url: string, pin: list> = {
  url: `https://d2lang.com/install.sh`
  pin: [--version v0.7.1]
}
const REGISTRY: record<scheme: string, host: string, path: string> = {
  scheme: https
  host: raw.githubusercontent.com
  path: /zaynram/nupm-registry/main/registry.nuon
}
const MODULES: list<string> = [issue tasks]

# Configure the project's local Git hooks.
export def git-hooks []: nothing -> nothing {
  if (which git | is-empty) {
    error make --unspanned 'ensure git is installed and on PATH'
  }
  try {
    git -C $ROOT config core.hooksPath .githooks
  } catch {
    error make 'unable to update git config with hooks path'
  }

  log info $"(ansi g)setup.git-hooks done(ansi rst)"
}

# Install the documentation system dependencies with `pipx`.
export def site-gen []: nothing -> nothing {
  if (which pipx | is-empty) { error make --unspanned 'ensure pipx is installed and on PATH' }

  let reqs: table<name: string, sep: string, version: string> = open $REQUIREMENTS
    | lines
    | compact --empty
    | where $it !~ ^#
    | parse --regex $REGEX
  let list: string = (pipx list --include-injected o+e>| to text)

  def is-not-installed []: record -> bool { get name version | str join \s+ | $list !~ $in }

  let main: record<name: string> = $reqs | first
  let deps: list = $reqs | skip 1 | where { is-not-installed } | par-each { values | str join }

  if ($main | is-not-installed) {
    log info $'installing ($main.name) v($main.version)'
    try {
      pipx install --force ($main | values | str join)
    } catch {
      error make $'($main.name) installation did not succeed'
    }
  }

  if ($deps | is-not-empty) {
    log info $'installing ($deps | length) dependencies'
    log debug $'- ($deps | str join "\n- ")'
    try {
      pipx inject --force $main.name ...$deps
    } catch {
      error make 'dependency injection did not succeed'
    }
  }

  log info $"(ansi g)setup.site-gen done(ansi rst)"
}

# Fetch and run the D2 install script.
export def fetch-d2 []: nothing -> oneof<nothing, string> {
  try {
    http get --raw --allow-errors $D2.url | sh -s -- ...$D2.pin
  } finally {
    log info $"(ansi g)setup.fetch-d2 done(ansi rst)"
  }
}

# Install the repository's `tasks` package globally with `nupm`.
#
# Runs iff nupm manages this machine ($env.NUPM_HOME is set to an existing
# directory); otherwise it logs the skip and returns. The nupm module loads in
# a child interpreter from $env.NUPM_HOME/modules, so the parse-time import
# cannot break environments without nupm.
export def nupm-tasks []: nothing -> nothing {
  # An unset home must not fall through: '' resolves to the current directory,
  # and `$env has NUPM_HOME and …` alone routes the unset case into the install
  # branch where the strict `$env.NUPM_HOME` access throws.
  if not ($env has NUPM_HOME) or ($env.NUPM_HOME | path type) != dir {
    log warning 'setup.nupm-tasks skipped; $env.NUPM_HOME is not a directory'
  } else {
    let registry: string = $REGISTRY | url join
    let include: path = $env.NUPM_HOME | path join modules
    # --no-confirm: any nupm prompt would hang invisibly in the captured child.
    let commands: string = $MODULES
      | par-each { $"nupm install --force --no-confirm --registry=ramda-doc ($in)" }
      | prepend 'use nupm'
      | str join '; '
    let temp_env = $env
      | select --optional NUPM_REGISTRIES
      | upsert NUPM_REGISTRIES { default {} | insert ramda-doc $registry }
    with-env $temp_env {
      ^$nu.current-exe ...[
        --no-config-file
        --include-path=($include)
        --commands=($commands)
      ] out+err>|
      | complete
      | if $in.exit_code != 0 {
        error make --unspanned $"`nupm install` did not succeed:\n($in.stdout?)"
      }
    }
    log info $"(ansi g)setup.nupm-tasks done(ansi rst)"
  }
}

# Run a selection of the setup functions.
export def main [
  ...subcommands: string@_empty # Spread list of subcommands to execute
  --git-hooks # Configure the Git hooks
  --site-gen # Run the SSG (+dependencies) installer
  --fetch-d2 # Curl and run the d2 installer
  --nupm-tasks # Install the `tasks` package globally with nupm
]: nothing -> nothing {
  let run: list = $subcommands | default --empty [git-hooks site-gen nupm-tasks]
  alias is-enabled = do {|name: string| $run has $name }
  if $git_hooks or (is-enabled git-hooks) { git-hooks }
  if $site_gen or (is-enabled site-gen) { site-gen }
  if $fetch_d2 or (is-enabled fetch-d2) { fetch-d2 }
  if $nupm_tasks or (is-enabled nupm-tasks) { nupm-tasks }
}

# Disable automatic path completions by returning an empty list.
def _empty []: nothing -> list { [] }

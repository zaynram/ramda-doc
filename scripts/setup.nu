#!/usr/bin/env -S nu --stdin

const NUON: path = path self injections.nuon

def main [
  --force # Force dependency reinjection
]: nothing -> nothing {
  if (which pipx | is-empty) {
    error make --unspanned 'ensure pipx is installed and on PATH'
  }
  if (which mkdocs | is-empty) {
    try { pipx install properdocs } catch {
      error make 'mkdocs installation did not succeed'
    }
  }
  let args: list<string> = if $force { [--force] } else { [] }
    | prepend [inject properdocs]
  for dep in (open $NUON) {
    try { pipx ...$args $dep } catch {
      get --optional rendered
      | default $'unable to inject ($dep)'
      | print --stderr
      match ([yes no] | input list continue?) { no => { break } }
    }
  }
}

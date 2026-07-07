#!/usr/bin/env -S nu --stdin
const DIR: path = path self .. | path expand
const NU_LIB_DIRS: list<path> = [$DIR]
def --wrapped main [
  ...rest: string # Arguments to pass through to `setup run`
  --import (-i) # Import the `setup` module without running any scripts
]: nothing -> nothing {
  if $import {
    export use setup
  } else {
    use setup
    setup ...$rest
  }
}

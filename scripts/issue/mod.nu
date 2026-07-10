const ROOT: path = path self ../.. | path expand
export const ISSUES: path = $ROOT | path join docs/issues
const SCHEMA: path = 'https://zaynram.github.io/ramda-doc/schema/issue.schema.json'

# Load an issue from its original TOML file.
export def main [
  slug: string@_issue-slugs # The slug of the target issue
  --md # Return the issue after formatting the data in Markdown
]: nothing -> record<name: string, slug: string, status: string> {
  let issue: path = build-path $slug
  if not ($issue | path exists) { error make --unspanned $"issue '($slug)' does not exist" }
  open $issue | get issue | if $md { build-md } else { }
}

# Fetch issue(s) from remote and ensure the local TOML is synced.
export def fetch [
  slug?: string@_issue-slugs # The slug for a specific issue to target
  --confirm (-c) # Display the update record(s) and await confirmation to write to disk
]: nothing -> oneof<table, nothing> {
  if $slug != null { [--search=($slug)] }
  | append '--json=number,title,state,url,createdAt'
  | gh issue list ...$in out+err>|
  | complete
  | if $in.exit_code != 0 or ($in.stdout? | is-empty) {
    error make --unspanned 'unable to fetch issues from remote'
  } else {
    get stdout
    | from json
    | into int number
    | into datetime createdAt
    | str downcase state
    | rename --column={number: index state: status createdAt: date}
    | update title { parse '{name} ({slug})' | into record }
    | insert name {|row| $row.title.name }
    | insert slug {|row| $row.title.slug }
    | reject title
    | par-each {|row|
      gh issue develop --list $row.index out+err>|
      | complete
      | if $in.exit_code != 0 or ($in.stdout | is-empty) {
        error make --unspanned $'unable to gather branch for issue #($row.index)'
      } else {
        get stdout
        | lines
        | skip 1
        | str join (char newline)
        | from tsv --noheaders
        | drop column
        | rename branch
        | into record
        | merge ($row | select index url)
      }
      | wrap reference
      | merge ($row | select name slug date status)
    }
    | collect
    | if $confirm {
      let changes: table = $in | enumerate
      let indices: list<int> = $changes.item.reference
        | rename --block { prepend reference | str join . }
        | merge ($changes.item | reject reference)
        | input list --multi 'Save changes' --index
      $changes | where index in $indices | get item
    } else { }
    | par-each {|row| edit $row.slug --merge=$row --diff }
    | compact --empty
    | default --empty { print '(no changes)' }
  }
}

# Get a value from an issue's TOML data.
export def query [
  slug: string@_issue-slugs # The slug of the target issue
  property?: cell-path@_properties # The cell-path(s) of the property values to return
]: nothing -> oneof<nothing, any> {
  if $property == null { return (_properties $slug) }
  main $slug | get --ignore-case --optional $property
}

# Edit an issue TOML by merging a Nushell record.
#
# Update data may be passed as an inline record with `--merge` and/or as pipeline input.
# If both are provided, the `--merge` record will take priority if their are overlapping keys.
#
## Notes
# * The final merged data will be piped to `wrap issue` before writing to disk.
# * The `--strategy` will be used for **all** merge operations.
# * Comments will not be preserved and `tombi format` is used if it is installed.
export def edit [
  slug: string@_issue-slugs # The slug of the issue to convert
  --merge (-m): record = {} # Property names mapped to their new values (merged into input)
  --strategy (-s): string@_strategies = table # The merge strategy to use for `merge deep`
  --diff (-d) # Return a record containing only the changes properties
  --return (-r) # Return the updated issue record
]: oneof<nothing, record> -> oneof<nothing, record> {
  let edit: record = $in
    | default {}
    | merge deep --strategy=$strategy $merge
  if ($edit | is-empty) { error make 'no changes were provided' }

  let base: record = main $slug
  let data: record = $base | merge deep --strategy=$strategy $edit

  if $base != $data {
    try {
      let text: string = $data | wrap issue | to toml | toml-fmt
      $text | save --force (build-path $slug)
    } catch {
      error make {
        msg: 'unable to serialize and write updated TOML'
        labels: [
          {text: issue span: (metadata $slug).span}
          {text: changes span: (metadata $merge).span}
        ]
      }
    }
    if $diff {
      $data | items {|k v|
        if $base has $k and ($base | get --optional $k) != $v { {$k: $v} }
      } | compact | into record
    }
  }

  $data
  | if not $return and not $diff {
    return null
  } else if not $diff {
    return $in
  } else {
    items {|k v| if $base has $k and ($base | get --optional $k) != $v { {$k: $v} } }
    | compact
    | if ($in | is-not-empty) { into record } else { return {} }
  }
}

# List the issues.
export def list [
  --glob (-g): glob = *.issue.toml # Glob expression for filtering issues to include
  ...select: cell-path@_columns # Columns to include in the output table
]: nothing -> table {
  let ls: table = cd $ISSUES
    | try { ls --full-paths $glob } catch { error make 'unable to collect issue files' }
    | reject size type
    | sort-by modified
  $ls | if ($in | is-empty) {
    error make --unspanned 'no issues matched the query'
  } else {
    insert source {|row| $row.name | path relative-to $ROOT }
    | update name {|row| path parse --extension=$'issue.toml' | get stem }
    | rename --column={name: slug modified: edited}
    | insert index {|row| query $row.slug reference.index }
    | insert url {|row| query $row.slug reference.url }
    | select --ignore-case --optional ...$select
    | compact --empty
  }
}

# Push an issue to the GitHub remote.
export def --wrapped push [
  slug: string@_issue-slugs # The issue slug to push to remote
  --labels (-l): list<string> = [documentation] # Label(s) to create the issue with
  --branch (-b): string # The name of the branch this issue will be handled on
  --resume (-r): path # Path to a temp file containing built Markdown to resume from
  --existing (-e) # Pass this to update an existing issue instead of creating a new one
  ...rest: string # Additional arguments to pass to `gh issue create`
]: nothing -> record<index: int, branch: string, url: string> {
  let base: record = main $slug
  let user: string = try { git config --get user.name } catch { '@me' } | str trim
  let desc: string = $base.name
    | split words
    | str capitalize
    | append $"\(($slug))"
    | str join (char space)
  let path: string = $resume | default {
      try {
        let temp: path = mktemp --suffix=md
        $base | build-md | save --force $temp
        return $temp
      } catch {
        error make 'unable to save markdown'
      }
    }
  let data: record = run-external ...[
    ...(if $existing { [gh issue edit $base.reference.index] } else { [gh issue create] })
    --title=($desc)
    --assignee=($user)
    --body-file=($path)
    ...($labels | each { prepend [--label] } | flatten)
    ...(if $resume != null { })
  ] ...$rest out+err>|
    | complete
    | if $in.exit_code != 0 or ($in.stdout? | is-empty) {
      let out: record = $in
      if $out has stdout { print --stderr $out.stdout }
      print --stderr $'to attempt a retry, pass `--resume="($path)"` with  `--recover=<string>`'
      error make 'issue creation failed'
    } else {
      get stdout
      | output-link
      | wrap url
      | insert branch ($branch | default $slug)
      | insert index {|row| $row.url | parse '{_}/issues/{index}' | first | into int index }
      | wrap reference
    }

  try { $data | edit $slug --return | get reference } finally { rm --force $path }
}

## Utilities

def build-path [slug: string]: nothing -> path {
  {parent: $ISSUES stem: $slug extension: issue.toml} | path join
}

def toml-fmt []: string -> string {
  if (which tombi | is-empty) { } else {
    tombi format --quiet - out+err>|
  }
}

def output-link []: string -> string {
  lines | where $it =~ github.com | str trim | first
}

def prop-table [
  --property: string
  --level: int
]: record -> list<string> {
  if ([$property $level] | any { $in == null }) {
    error make --unspanned 'all flags are mandatory'
  } else {
    let value: any = $in | get --optional --ignore-case $property
    if ($value | is-empty) { return [] }
    let type: string = $value | describe | split words | first
    alias cap = do { split words | str capitalize | str join (char space) }
    alias col-cap = do { rename ...($in | columns | each { cap }) }
    match $type {
      list => { $value | to md --per-element }
      record => {
        $value | col-cap
        | items {|k v| $"**($k)**: ($v | to text)\n" }
        | to md --per-element --pretty
      }
      table => { $value | col-cap | to md --pretty --per-element }
      _ => {
        error make {
          msg: $'unsupported value type: ($type)'
          label: {text: property span: (metadata $property).span}
        }
      }
    }
    | append "\n"
    | prepend $"(1..$level | each { '#' } | str join) ($property | cap)\n"
  }
}

def build-md []: record<name: string, slug: string, status: string> -> string {
  let issue: record = $in | default {} reference vision bindings
  let props: record = [vision bindings]
    | par-each {|prop| [$prop ($issue | get --optional $prop | default {} | columns)] }
    | into record
  let vision: list<string> = $props.vision
    | each {|prop|
      match $prop {
        landscape if ($issue.vision.landscape.external? | describe) =~ ^record => {
          let base = $issue.vision.landscape.external
          $base | columns
          | each {|col| $base | prop-table --property=$col --level=5 }
          | flatten
          | prepend [
            $"### Landscape\n"
            ...($issue.vision.landscape | prop-table --property=internal --level=4)
            "#### External\n"
          ]
        }
        outcome if $issue.vision.outcome.mode? == compound => {
          $issue.vision.outcome
          | prop-table --property=threads --level=4
          | prepend [
            $"### ($prop | str capitalize)\n"
            $"**Mode:** ($issue.vision.outcome.mode)\n"
          ]
        }
        scope | criteria | output | landscape => {
          let base = $issue.vision | get --optional $prop
          try {
            $base | columns
            | each {|col| $base | prop-table --property=$col --level=4 }
            | flatten
            | prepend $"### ($prop | str capitalize)\n"
          } catch {
            $issue.vision | prop-table --property=$prop --level=3
          }
        }
        _ => { $issue.vision | prop-table --property=$prop --level=3 }
      }
    }
    | flatten
    | prepend "## Vision\n"
  let bindings: list<string> = $props.bindings
    | each {|prop| $issue.bindings | prop-table --property=$prop --level=3 }
    | flatten
    | prepend "## Bindings\n"
  [
    $"# ($issue.name) \(($issue.slug))"
    ...$vision
    ...$bindings
  ]
  | str join (char newline)
  | md-fmt
}

def md-fmt []: string -> string {
  if (which rumdl | is-empty) { return $in } else {
    rumdl fmt --silent --flavor=github --stdin
  }
}

## Completions

def _strategies []: nothing -> list { [append overwrite prepend table] }

def _issue-slugs []: nothing -> list {
  let exp: glob = $ISSUES | path join *.issue.toml
  glob $exp --exclude=[**/*.draft.toml] --no-symlink --no-dir
  | path parse --extension=issue.toml
  | get stem
}
def _columns [context: string]: nothing -> list {
  let words: list<string> = $context | split words
  [index slug edited source url] | where $it not-in $words
}

const V2_PROPERTIES: list<cell-path> = [
  version
  name
  slug
  date
  status
  reference
  reference.index
  reference.branch
  reference.url
  vision
  vision.criteria
  vision.output
  vision.outcome
  vision.scope
  vision.landscape
  bindings
  bindings.xvalue
  bindings.xabort
]

def _properties [context: string]: nothing -> list<string> {
  let list: list = _issue-slugs
  let slug: string = $list | where $context =~ $it | first
  if ($slug | is-not-empty) {
    main $slug
    | default {} reference vision bindings
    | items {|property item|
      match $property {
        reference | vision | bindings => [
          $property
          ...($item | columns | each { prepend $property | str join . })
        ]
        _ => [$property]
      }
    }
    | compact --empty
    | flatten
    | uniq --ignore-case
  } else {
    $V2_PROPERTIES
  }
}

const ROOT: path = path self ../.. | path expand
export const ISSUES: path = $ROOT | path join docs/issues
const SCHEMA: path = 'https://zaynram.github.io/ramda-doc/schema/issue.schema.json'

# Load an issue from its original TOML file.
export def load [
  slug: string@_issue-slugs # The slug of the target issue
]: nothing -> record<slug: string, date: datetime, status: string, vision: record, bindings: record> {
  let issue: path = build-path $slug
  if not ($issue | path exists) { error make --unspanned $"issue '($slug)' does not exist" }
  open $issue | get issue
}

# Get a value from an issue's TOML data.
export def query [
  slug: string@_issue-slugs # The slug of the target issue
  property?: cell-path@_properties # The cell-path(s) of the property values to return
]: nothing -> oneof<nothing, any> {
  if $property == null { return (_properties $slug) }
  load $slug | get --ignore-case --optional $property
}

# Convert an issue from TOML to a Markdown code block for rendering.
export def convert [
  slug: string@_issue-slugs # The slug of the issue to convert
]: nothing -> oneof<record, path> {
  build-path $slug | try {
    open --raw
    | skip 2 # Skip the schema declaration and TOML version
    | lines
    | where $it !~ '^#'
    | str trim --right
    | prepend r#'```toml'#
    | append r#'```'#
    | str join (char newline)
  } catch {
    error make {
      msg: 'conversion did not succeed'
      label: {text: issue span: (metadata $slug).span}
    }
  }
}

# List the issues.
export def list [
  --glob: glob = *.issue.toml # Glob expression for filtering issues to include
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
  --title (-t): string # The title to use for the issue
  --assignee (-a): string # Who to assign the issue to
  --label: string # Label to create the issue with
  --body: string # Use this text as the body for the issue
  ...rest: string # Additional arguments to pass to `gh issue create`
]: nothing -> nothing {
  let title: string = $title
    | default --empty {
      let name: string = query $slug name
      if ($name | is-not-empty) {
        $name + ' (' + $slug + ')'
      } else {
        $slug | split words | str join (char space) | str capitalize
      }
    }
  let assignee: string = $assignee
    | default { git config --get user.name | to text | str trim }
    | default --empty { whoami }
  let label: string = $label
    | default documentation
  let body: string = $body
    | default --empty { convert $slug }
  try {
    gh issue create --title $title --assignee $assignee --body $body --label $label ...$rest
    | to text | lines | str trim | compact --empty | last
  } catch {
    error make 'issue creation did not succeed'
  } | do {|url: string rec: record toml: path|
    let n: int = parse 'https://github.com/zaynram/ramda-doc/issues/{index}'
      | get index
      | into int
      | first
    let old: record = $rec.reference? | default {}
    let new: record = $old | merge {index: $n url: $url}
    {issue: ($rec | upsert reference $new)}
    | to toml
    | prepend [
      $"#:schema ($SCHEMA)"
      "#:tombi toml-version = 'v1.1.0'"
      ""
    ] | save --force $toml
  } $in (load $slug) (build-path $slug)
}

## Utilities

def build-path [slug: string]: nothing -> path {
  {parent: $ISSUES stem: $slug extension: issue.toml} | path join
}

## Completions

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
    load $slug
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

# nu-lint-ignore-file: positional_to_pipeline, chained_str_transform, missing_in_type, missing_output_type

const PROJECTS: directory = $nu.home-dir | path join code
const GLOBAL: record<name: string, path: oneof<nothing, directory>> = {
  name: global
  path: $PROJECTS
}
# Issue-schema version the importer understands; imports from other versions
# proceed with a warning.
const SCHEMA_VERSION: string = '3.0.0'
const DB: record = {
  name: tasks
  file: ($nu.data-dir | path join stor nudb.sqlite)
  columns: {
    id: str
    date: datetime
    project: jsonb
    subtasks: jsonb
    target: str
    completed: str
    source: jsonb
  }
  types: {
    id: string
    date: datetime
    project: `record<name: string, path: directory>`
    subtasks: `record<[int]: record<synopsis: string, done: bool, llm: string>>`
    target: `oneof<nothing, string>`
    completed: `oneof<nothing, string>`
    source: `oneof<nothing, record<path: path, key: string>>`
  }
  enums: {
    subtasks.llm: [none augmentation automation]
  }
}

# Retrieve tasks from the in-memory database.
export def list [
  --field (-f): string@_db-fields # Get the value(s) for this field only
  --id: string@_task-ids # Filter by task ID likeness ('%' = str wildcard, '_' = char wildcard)
  --project: string@_project-names # Filter by exact project name
  --sync = true # Pull source-file edits into the database first
]: nothing -> table {
  ensure-db --sync=$sync
  let select: string = append $field | default --empty [*] | str join ,
  let where: string = [
    (if $id != null { $"id LIKE '($id | sql-str)'" })
    (if $project != null { $"project->>'name' = '($project | str trim --char / | sql-str)'" })
  ] | compact | str join ' AND '
  query-tasks --select $select --where $where
}

# Add a task to the in-memory `tasks` database.
export def add [
  id: string # Descriptive identifier for the task
  --project (-p): string@_project-names # The project associated with the task
  --subtasks (-s): table<synopsis: string> # Subtasks for this task (appended to pipeline input)
  --write (-w) = true # Automatically write the database to disk after adding the task
]: [
  nothing -> nothing
  table<synopsis: string> -> nothing
] {
  ensure-db
  | append $subtasks
  | compact
  | subtask-pack
  | wrap subtasks
  | insert id $id
  | insert date { date now }
  | insert project { get-project $project }
  | stor insert --table-name $DB.name
  | if $write { dump } else { ignore }
}

# Import tasks from an issue file's `tasks` property, tracking the file as their source.
#
# The file is the source of truth: re-importing refreshes existing rows,
# prunes rows whose entry vanished, and retargets the source path when the
# file has moved. CLI changes to imported tasks sync back automatically.
export def import [
  file: path # Issue file compliant with the issue schema's `tasks` property
  --write (-w) = true # Automatically write the database to disk after importing
]: nothing -> table {
  # Importing IS the sync for this file; skip the global refresh.
  ensure-db --sync=false
  let out: table = import-file ($file | path expand)
  if $write { dump }
  $out
}

# Relink an imported task to its source file's new location.
#
# The task's entry key is rediscovered by id, and no sync occurs until the
# next CLI change — the file's current content is left untouched.
export def retarget [
  id: string@_task-ids # The imported task to relink
  file: path # The new location of the source file
  --write (-w) = true # Automatically write the database to disk after relinking
]: nothing -> record {
  # The repair path must not trip over the breakage it exists to fix.
  ensure-db --sync=false
  let path: path = $file | path expand
  let task: any = query-tasks --select 'id, source' --where $"id LIKE '($id | sql-str)' AND source IS NOT NULL" | first
  if $task == null {
    error make --unspanned $"no imported task matches id '($id)'"
  }
  let key: any = open $path
    | get --optional tasks
    | default {}
    | items {|k t| if $t.id? == $task.id { $k } }
    | compact
    | first
  if $key == null {
    error make --unspanned $"($path) does not define task '($task.id)'"
  }
  let source: record = {path: $path key: $key}
  stor update --table-name $DB.name --update-record {source: $source} --where-clause $"id = '($task.id | sql-str)'"
  if $write { dump }
  {id: $task.id source: $source}
}

# Update a task from the in-memory database.
export def edit [
  id: string@_task-ids # The id of the task to update (can include wildcards)
  --set-clause: string # Raw SET query string (without leading SET; cannot be combined with other flags)
  --update: record = {} # Record containing changes to make to the task
  --subtask: closure # Replace the subtasks with the resulting table of a closure given the subtasks as input and the whole task as an argument.
  --set-project: string@_project-names # Update the project record to target this project
  --sync = true # Pull source-file edits into the database first
  --check = true # Run tombi against source files after updating them
  --commit = true # Record syncs as commits in the source repositories
]: oneof<nothing, record> -> table {
  let input: any = $in
  ensure-db --sync=$sync
  if $set_clause != null {
    # `any`: stor/query db mutations return a SQLiteDatabase handle, not a table.
    let out: any = query-tasks --set $set_clause --where $"id LIKE '($id | sql-str)'"
    sync-sources $id --check=$check --commit=$commit
    return $out
  }
  let base: record = $input | default {} | merge $update
  let subbed: record = match $subtask {
    null => $base
    $s => {
      query-tasks --select subtasks --where $"id LIKE '($id | sql-str)'"
      | into record
      | upsert subtasks $s
      | upsert subtasks { subtask-pack }
      | merge $base
    }
  }
  let data: record = match $set_project {
    null => $subbed
    $p => { $subbed | upsert project (get-project $p) }
  }
  if ($data | is-empty) {
    error make --unspanned 'no update data was provided'
  }
  $data | update-tasks $id --check=$check --commit=$commit
}

# Remove a task from the in-memory database and from its source file.
export def del [
  where?: string
  --id: string@_task-ids # Delete the task holding this id
  --all # Delete all tasks
  --sync = true # Pull source-file edits into the database first
  --check = true # Run tombi against source files after updating them
  --commit = true # Record syncs as commits in the source repositories
]: nothing -> table {
  ensure-db --sync=$sync
  let clause: any = $where | default (if $id != null { $"id LIKE '($id | sql-str)'" })
  if $clause == null and not $all {
    error make --unspanned 'filter is required without `--all`'
  }
  # File truth cuts both ways: drop the source entry too, or the next
  # refresh would just resurrect the task. A missing file only warns —
  # nothing is left behind to resurrect from.
  let sourced: string = [$clause 'source IS NOT NULL'] | compact | str join ' AND '
  for task in (query-tasks --select 'id, project, source' --where $sourced) {
    try {
      let path: path = $task | heal-source
      let entries: record = open $path | get --optional tasks | default {}
      # Id-authoritative: drop whichever key currently holds this task.
      let key: string = $entries
        | items {|k t| if $t.id? == $task.id { $k } }
        | compact
        | first
        | default $task.source.key
      $entries
      | items {|k t| if $k != $key { {($k): $t} } }
      | compact
      | into record
      | write-source $path --check=$check --commit=$commit
    } catch {|e| print --stderr $"warning: ($e.msg)" }
  }
  match $clause {
    null => { stor delete --table-name $DB.name }
    $w => { stor delete --table-name $DB.name --where-clause $w }
  }
}

# Revert a task's most recent synced change using its source repository.
#
# Restores the source file to its state before the last sync commit on the
# task's branch, re-imports it, and records the reversion as a new sync
# commit — so undoing an undo redoes. Refuses when non-sync commits touched
# the file since, rather than clobbering manual history.
export def undo [
  id: string@_task-ids # The imported task whose last synced change to revert
  --write (-w) = true # Automatically write the database to disk after reverting
]: nothing -> table {
  # No refresh: the working file is about to be rewritten from history.
  ensure-db --sync=false
  let task: any = query-tasks --select 'id, project, source' --where $"id LIKE '($id | sql-str)' AND source IS NOT NULL" | first
  if $task == null {
    error make --unspanned $"no imported task matches id '($id)'"
  }
  let path: path = $task | heal-source
  let dir: directory = $path | path dirname
  if (do { ^git -C $dir rev-parse --is-inside-work-tree } | complete).exit_code != 0 {
    error make --unspanned $"($path) is not in a git repository; there is no history to undo from"
  }
  let head: string = do { ^git -C $dir symbolic-ref --short --quiet HEAD } | complete | get stdout | str trim
  let branch: any = (open $path).issue?.reference?.branch?
  let target: string = if ($branch | is-empty) { $head } else { $branch }
  let root: path = ^git -C $dir rev-parse --show-toplevel | str trim
  let rel: string = $path | path relative-to $root
  # Absolute pathspecs: `log -- <path>` resolves relative to the cwd, and the
  # repo-root-relative form would silently miss from inside a subdirectory.
  let last_sync: string = do { ^git -C $dir log -1 --format=%H --grep '^tasks: ' $target -- $path } | complete | get stdout | str trim
  if ($last_sync | is-empty) {
    error make --unspanned $"no sync commits touch ($rel) on '($target)'"
  }
  let last_touch: string = ^git -C $dir log -1 --format=%H $target -- $path | str trim
  if $last_touch != $last_sync {
    error make --unspanned $"($rel) has non-sync commits after its last sync on '($target)'; revert manually"
  }
  let prev: string = try { ^git -C $dir show $"($last_sync)^:($rel)" } catch {
    error make --unspanned $"($rel) does not exist before its first sync; nothing to restore"
  }
  $prev | save --force --raw $path
  let subject: string = ^git -C $dir log -1 --format=%s $last_sync | str trim
  commit-source $path $"tasks: undo ($path | path basename)\n\nThis reverts ($last_sync | str substring 0..11) \(($subject))." $branch
  let out: table = import-file $path
  if $write { dump }
  $out
}

# Interact with subtasks.
#
# Inserting a subtask at an index will shift all higher indices up one.
# Popping a subtask at an index will shift all higher indices down one.
export def sub [
  id: string@_task-ids # Task to retrieve subtasks from
  --add (-a): record<synopsis: string> # Add a subtask for this task
  --index (-i): record # Insert subtask(s) given as {<index>: <subtask>}
  --set (-s): record # Merge partial fields into subtask(s) given as {<index>: <partial record>}
  --done (-d): int = -1 # Mark the subtask at an index as done (undo via --set {<index>: {done: false}})
  --pop (-p): int = -1 # Pop a subtask at an index
  --sync = true # Pull source-file edits into the database first
  --check = true # Run tombi against source files after updating them
  --commit = true # Record syncs as commits in the source repositories
]: nothing -> table {
  ensure-db --sync=$sync
  let task: any = query-tasks --select 'id, subtasks' --where $"id LIKE '($id | sql-str)'"
    | if ($in | is-empty) { error make --unspanned $"no task matches id '($id)'" } else { first }
  let subs: list = $task | subtask-hydrate | sort-by index | get item
  # ponytail: -1 (the default) for --done/--pop means "not requested" — an
  # explicit -1 is indistinguishable from the default, so target real indices.
  match ({add: $add index: $index set: $set} | compact | columns | first) {
    add => { $subs | append ($add | subtask-default) }
    index => {
      $index
      | wrap subtasks
      | subtask-hydrate
      | sort-by index
      | reduce --fold $subs {|it acc| $acc | insert $it.index $it.item }
    }
    set => {
      $set
      | items {|n patch| {index: ($n | into int) patch: $patch} }
      | reduce --fold $subs {|it acc| $acc | update $it.index { merge $it.patch } }
    }
    _ if $done >= 0 => { $subs | update $done { upsert done true } }
    _ if $pop >= 0 => { $subs | drop nth $pop }
  }
  | if $in != null {
    let changed = $in
    $changed | subtask-pack | wrap subtasks | update-tasks $task.id --check=$check --commit=$commit
    $changed
  } | default $subs | enumerate | flatten
}

# Summarize subtask progress for each task.
export def main [
  project?: string@_project-names # Filter by exact project name
  --sync = true # Pull source-file edits into the database first
]: nothing -> table {
  if $project == null { list --sync=$sync } else { list --sync=$sync --project $project }
  | par-each --keep-order {|t|
    subtask-hydrate
    | do {|subs: table|
      | length
      | wrap total
      | insert done { $subs | where $it.item.done | length }
    } $in
    | merge ($t | select id date)
    | insert project $t.project.name
  }
}

# Return the database schema or information about its types.
export def meta [
  --list-columns (-c) # Return the database columns and data types
  --list-types (-t) # Return the Nushell columns and types for the update record
  --list-enums (-e) # Return the values for enumerables
]: nothing -> record {
  if $list_columns { return $DB.columns }
  if $list_types { return $DB.types }
  if $list_enums { return $DB.enums }
  ensure-db; stor open | schema
}

# Load the database into process memory.
#
# Any database operation will automatically load the database if it has not been already.
# This function exists for cases where a manual reload is necessary, especially if a session reload is not a viable option.
export def load [
  --silent (-s) # Return `null` instead of the tasks table after initialization
]: nothing -> oneof<nothing, table> {
  let query: string = $"SELECT name FROM sqlite_master WHERE type='table' AND name='($DB.name)'"
  if (stor open | query db $query | is-empty) {
    if ($DB.file | path exists) {
      stor import --file-name $DB.file
      # ponytail: cp not mv — mv stranded the canonical DB on any read-only
      # session (all tasks lost to .bak); cp keeps it in place, .bak is a backup.
      cp --force --update $DB.file $'($DB.file).bak'
    } else {
      stor create --table-name $DB.name --columns $DB.columns
      mkdir ($DB.file | path dirname)
    }
    # Ids are unique; projects are shared. project_idx was historically UNIQUE,
    # capping every project at a single task — drop and rebuild it plain.
    stor open | query db $"CREATE UNIQUE INDEX IF NOT EXISTS task_idx ON ($DB.name) \(id)"
    stor open | query db 'DROP INDEX IF EXISTS project_idx'
    stor open | query db $"CREATE INDEX project_idx ON ($DB.name) \(project->'name')"
    # Migrate databases created before a column existed in $DB.columns.
    let have: list = stor open | query db $"PRAGMA table_info\(($DB.name))" | get name
    for col in ($DB.columns | columns | where $it not-in $have) {
      stor open
      | query db $"ALTER TABLE ($DB.name) ADD COLUMN ($col) ($DB.columns | get --optional $col)"
    }
  }
  if $silent { return } else { list }
}

# Persist the tasks from the in-memory database.
#
# Exports to a sibling temp file first so a failed export can never
# destroy the canonical database.
export def dump []: nothing -> nothing {
  # --sync=false: dump persists what is in memory; the invoking command
  # already refreshed, and a second sweep would just re-read every source.
  ensure-db --sync=false
  let tmp: path = $'($DB.file).tmp'
  rm --force $tmp
  stor export --file-name $tmp
  mv --force $tmp $DB.file
}

## Utilities

# Ensure the database has been initialized and mirrors the source files.
# Captures and returns any pipeline input for use at the start of database operation functions.
def ensure-db [
  --sync = true # Pull source-file edits into the database after loading
]: any -> any {
  let input: any = $in
  load --silent
  if $sync { refresh-sources }
  $input
}

# Pull file-side edits into the database: the file is the source of truth.
# Failures degrade to warnings so a broken source never bricks the CLI;
# `tasks retarget` remains the repair path.
def refresh-sources []: nothing -> nothing {
  let paths: list = query-tasks --select 'id, project, source' --where 'source IS NOT NULL'
    | each {|t| try { $t | heal-source } catch {|e| print --stderr $"warning: ($e.msg)"; null } }
    | compact
    | uniq
  for path in $paths {
    try { import-file $path | ignore } catch {|e|
      print --stderr $"warning: refresh from ($path) failed: ($e.msg)"
    }
  }
}

# Parse an issue file and mirror its `tasks` table into the database.
def import-file [path: path]: nothing -> table {
  let doc: record = open $path
  let version: string = $doc | get --optional version | default $SCHEMA_VERSION
  if $version != $SCHEMA_VERSION {
    print --stderr $"warning: ($path) declares schema ($version) but import is pinned to ($SCHEMA_VERSION); verify the tasks shape still matches"
  }
  let entries: record = $doc | get --optional tasks | default {}
  let sourced: string = $"source->>'path' = '($path | sql-str)'"
  if ($entries | is-empty) and (query-tasks --select id --where $sourced | is-empty) {
    error make --unspanned $"($path) has no tasks to import"
  }
  let project: record = try {
    get-project ($path | path relative-to $PROJECTS | path split | first)
  } catch { $GLOBAL }
  let rows: table = $entries | items {|key t|
      {
        id: $t.id
        date: (date now)
        project: $project
        subtasks: ($t.subtasks | subtask-pack)
        target: ($t.target? | default null)
        # match, not `not`: completed is false | date-string, and boolean
        # `not` on the date-string form throws. A TOML LocalDate parses as a
        # datetime — store the plain date string the schema means by it.
        completed: (
          match ($t.completed? | default false) {
            false => null
            $c if ($c | describe) == datetime => ($c | format date %F)
            $c => $c
          }
        )
        source: {path: $path key: $key}
      }
    }
  for row in $rows {
    let extant: any = query-tasks --select 'id, source' --where $"id = '($row.id | sql-str)'" | first
    match $extant {
      null => { $row | stor insert --table-name $DB.name | ignore }
      {source: null} => {
        error make --unspanned $"task '($row.id)' already exists without a source; rename one of them"
      }
      # The refresh flows through update-tasks, whose sync is a no-op here
      # because the database now mirrors the file exactly.
      _ => { $row | reject date | update-tasks $row.id | ignore }
    }
  }
  # Prune: the file owns existence, so rows whose entry vanished go away.
  let keep: string = $rows | each { $"'($in.id | sql-str)'" } | str join ', '
  stor delete --table-name $DB.name --where-clause (
    [
      $sourced
      (if ($rows | is-empty) { } else { $"id NOT IN \(($keep))" })
    ] | compact | str join ' AND '
  )
  if ($rows | is-empty) { [] } else { $rows | reject date project subtasks }
}

def get-project [name: oneof<nothing, string>]: nothing -> record<name: string, path: oneof<nothing, directory>> {
  if $name == null { return $GLOBAL }
  cd $PROJECTS
  glob $name --no-file
  | if ($in | is-empty) {
    error make --unspanned $"no project directory matches '($name)'"
  } else { first }
  | wrap path
  | insert name $name
}

def update-tasks [
  id: oneof<nothing, string>
  --check = true # Run tombi against source files after updating them
  --commit = true # Record syncs as commits in the source repositories
]: record -> table {
  let data: record = $in
  # `any`: stor update returns a SQLiteDatabase handle, not a table.
  let out: any = match $id {
    null => (
      stor update
      --table-name $DB.name
      --update-record $data
    )
    _ => (
      stor update
      --table-name $DB.name
      --update-record $data
      --where-clause $"id LIKE '($id | sql-str)'"
    )
  }
  # A task whose every subtask is done is completed; stamp the date once.
  # Un-doing a subtask does not reopen the task — clear completed manually.
  let where: string = if $id == null { '' } else { $"id LIKE '($id | sql-str)'" }
  for t in (query-tasks --select 'id, subtasks, completed' --where $where) {
    let subs: table = $t | subtask-hydrate
    if ($subs | is-not-empty) and ($subs | all { $in.item.done }) and $t.completed == null {
      stor update --table-name $DB.name --update-record {
        completed: (date now | format date %F)
      } --where-clause $"id = '($t.id | sql-str)'"
    }
  }
  sync-sources $id --check=$check --commit=$commit
  $out
}

# Write imported tasks matching the id likeness back to their source files.
#
# Skips the write when the file already matches, so no-op syncs (e.g. a
# re-import) never churn formatting or mtimes.
def sync-sources [
  id: oneof<nothing, string>
  --check = true # Run tombi against source files after updating them
  --commit = true # Record syncs as commits in the source repositories
]: nothing -> nothing {
  let where: string = [
    'source IS NOT NULL'
    (if $id != null { $"id LIKE '($id | sql-str)'" })
  ] | compact | str join ' AND '
  for task in (query-tasks --select * --where $where) {
    let path: path = $task | heal-source
    let doc: record = open $path
    let entries: record = $doc | get --optional tasks | default {}
    # Guard against key drift (file-side renumbering): the entry holding this
    # task's id is authoritative; writing at a stale key could clobber a
    # different task's entry.
    let by_id: any = $entries | items {|k t| if $t.id? == $task.id { $k } } | compact | first
    let owner: any = $entries | items {|k t| if $k == $task.source.key { $t.id? } } | compact | first
    let key: any = match [$by_id $owner] {
      [null null] => $task.source.key
      [null _] => null
      _ => $by_id
    }
    if $key == null {
      error make --unspanned $"key ($task.source.key) in ($path) now belongs to '($owner)' and '($task.id)' is not defined there; re-import or `tasks retarget`"
    }
    if $key != $task.source.key {
      # Direct stor update: routing through update-tasks would re-enter sync.
      stor update --table-name $DB.name --update-record {
        source: ($task.source | update key $key)
      } --where-clause $"id = '($task.id | sql-str)'"
    }
    let entry: record = {
      id: $task.id
      target: $task.target
      # Normalize to the schema's plain date: an `edit --update` given a
      # bareword date lands as a datetime, which would sync a full timestamp.
      completed: (
        match $task.completed {
          null => false
          $c => { try { $c | into datetime | format date %F } catch { $c } }
        }
      )
      subtasks: ($task | subtask-hydrate | sort-by index | get item | select synopsis llm done)
    }
    # Rebuild via shallow merge: in-place upsert chokes on digit keys (cell
    # paths read them as list indices) and on completed's false -> date shift.
    $entries | merge {($key): $entry} | write-source $path --check=$check --commit=$commit
  }
}

# Persist a source file's `tasks` table (given as input), leaving the rest
# of the document alone. Skips the write when the file already matches, so
# no-op syncs never churn formatting or mtimes.
#
# TOML sources are spliced textually — only the [tasks] section is rewritten —
# because a full parse/serialize round-trip mangles the rest of the document
# (local dates gain timestamps; comments and hand alignment vanish).
def write-source [
  path: path
  --check = true # Run tombi against the file after writing it
  --commit = true # Record the sync as a commit in the file's repository
]: record -> nothing {
  # Normalized on both sides or a TOML LocalDate (parsed as datetime) never
  # equals the database's date string, and the skip below stops skipping.
  let tasks: record = $in | normalize-completed
  let doc: record = open $path
  let old: record = $doc | get --optional tasks | default {} | normalize-completed
  if $old == $tasks { return }
  match ($path | path parse).extension {
    toml => {
      let lines: list = open --raw $path | lines
      # The schema types a completed date as a TOML LocalDate; `to toml` can
      # only quote it as a string, so unquote date-valued keys. Anchored to
      # whole lines: a quoted `key = "date"` is the entire line in generated
      # output, and anything looser can truncate a synopsis containing one.
      let body: string = {tasks: $tasks} | to toml | str trim --right
        | str replace --all --regex '(?m)^(?<key>\w+)\s*=\s*"(?<date>\d{4}-\d{2}-\d{2})"$' '$key = $date'
      let heads: list = $lines | enumerate | where ($it.item | is-tasks-header) | get index
      let text: string = if ($heads | is-empty) {
        [...$lines '' $body] | str join "\n"
      } else {
        # The section runs from the first tasks-scoped header to the next
        # foreign header. ponytail: a later interleaved [tasks.*] section or a
        # root-level `tasks.N = ...` assignment escapes the splice and yields a
        # duplicate table — tombi flags it; restructure the file if it ever bites.
        let start: int = $heads | first
        let end: any = $lines
          | enumerate
          | skip ($start + 1)
          | where item =~ '^\s*\[' and not ($it.item | is-tasks-header)
          | get --optional 0.index
        [
          ...($lines | take $start)
          $body
          ...(if $end == null { [] } else { ['' ...($lines | skip $end)] })
        ] | str join "\n"
      }
      ($text | str trim --right) + "\n" | save --force --raw $path
    }
    json => {
      $doc | merge {tasks: $tasks} | to json --indent 4 | save --force --raw $path
    }
    _ => {
      error make --unspanned $'unsupported file format: ($path | path parse | get extension)'
    }
  }
  if $check { check-source $path }
  if $commit { commit-source $path ($old | sync-summary $tasks $path) $doc.issue?.reference?.branch? }
}

# Validate a just-written source file with the format's linter, when one is
# installed. Lint failures warn — the sync itself already succeeded.
def check-source [path: path]: nothing -> nothing {
  # Run from the file's directory so the project's config (and its
  # schema association) is discovered; unconfigured projects lint syntax only.
  let lint: list<string> = match ($path | path parse).extension {
    toml if (which tombi | is-not-empty) => [tombi lint]
    _ => { return }
  }
  cd ($path | path dirname)
  run-external ...$lint ($path | path basename) out+err>|
  | complete
  | if $in.exit_code != 0 {
    let out: string = $in.stdout
    use std/log warning
    warning --short $"`($lint | str join ' ')` exited with a non-zero exit code"
    warning --short $"[stderr]\n($out)"
  }
}

# Compose a commit message describing a sync: subject plus one line per
# added (+), removed (-), or changed (~) entry with the fields that moved.
def sync-summary [tasks: record path: path]: record -> string {
  let old: record = $in
  [
    $"tasks: sync ($path | path basename)"
    ''
    ...(
      ($old | columns) ++ ($tasks | columns) | uniq | each {|k|
        let o: any = $old | get --optional $k
        let n: any = $tasks | get --optional $k
        match [$o $n] {
          [null _] => $"+ ($n.id? | default $k)"
          [_ null] => $"- ($o.id? | default $k)"
          _ if $o == $n => null
          _ => {
            let fields: string = $n | columns
              | where {|c| ($o | get --optional $c) != ($n | get --optional $c) }
              | str join ', '
            $"~ ($n.id? | default $k): ($fields)"
          }
        }
      } | compact
    )
  ] | str join "\n"
}

# Record the sync in the source file's repository, when it lives in one.
# Pathspec-scoped: only the synced file is committed, never other dirty or
# staged work. Failures warn — the file write already succeeded.
#
# An issue file's declared work branch ($.issue.reference?.branch?) is the
# commit target; without one, the checked-out branch is. A declared branch
# that is not checked out receives the commit in place via plumbing — the
# working tree is never switched — so the sync lands on the issue's branch
# even while the repository sits elsewhere.
def commit-source [path: path message: string branch: oneof<nothing, string>]: nothing -> nothing {
  let dir: directory = $path | path dirname
  if (do { ^git -C $dir rev-parse --is-inside-work-tree } | complete).exit_code != 0 { return }
  let head: string = do { ^git -C $dir symbolic-ref --short --quiet HEAD } | complete | get stdout | str trim
  let target: string = if ($branch | is-empty) { $head } else { $branch }
  if $target == $head {
    let commit: record = do {
      ^git -C $dir add -- $path
      ^git -C $dir commit --quiet --message $message -- $path
    } | complete
    if $commit.exit_code != 0 {
      use std/log warning
      warning --short $"git commit failed for ($path)"
      warning --short $"[stderr]\n($commit.stderr)"
    }
    return
  }
  try {
    let parent: string = ^git -C $dir rev-parse --verify --quiet $"refs/heads/($target)" | str trim
    let root: path = ^git -C $dir rev-parse --show-toplevel | str trim
    let blob: string = ^git -C $dir hash-object -w -- $path | str trim
    # Stage the synced content into the current checkout's index too: checkout
    # refuses to switch over an unstaged modification (it compares against the
    # index, not the target), while a staged entry equal to the target's blob
    # carries across cleanly — no stash dance to reach the issue branch.
    ^git -C $dir add -- $path
    let idx: path = mktemp --tmpdir tasks-git-index-XXXXXX
    let tree: string = with-env {GIT_INDEX_FILE: $idx} {
      ^git -C $dir read-tree $parent
      ^git -C $dir update-index --add --cacheinfo $"100644,($blob),($path | path relative-to $root)"
      ^git -C $dir write-tree | str trim
    }
    rm --force $idx
    # The branch may already carry this exact content (e.g. synced there by
    # another checkout); an empty commit would only be noise.
    if $tree == (^git -C $dir rev-parse $"($parent)^{tree}" | str trim) { return }
    let commit: string = $message | ^git -C $dir commit-tree $tree -p $parent | str trim
    # Compare-and-swap on the parent: never clobber a ref that moved under us.
    ^git -C $dir update-ref $"refs/heads/($target)" $commit $parent
  } catch {
    use std/log warning
    warning --short $"could not commit the sync of ($path | path basename) to branch '($target)' \(does it exist?); the change is written but uncommitted"
  }
}

# Render entry completed datetimes as plain date strings.
def normalize-completed []: record -> record {
  items {|k t|
    if $t not-has completed or ($t.completed | describe) == bool { $t } else {
      try { $t | update completed { into datetime | format date %F } } catch { $t }
    } | wrap $k
  } | into record
}

# True for TOML headers scoped under the root `tasks` table:
# [tasks], [tasks.0], [[tasks.0.subtasks]], ["tasks".0], ...
def is-tasks-header []: string -> bool {
  let t: string = $in | str trim
  if not ($t | str starts-with '[') { return false }
  let name: string = $t | str replace --regex '^\[+\s*"?' ''
  ['tasks]' tasks. 'tasks"'] | any {|p| $name | str starts-with $p }
}

# Resolve a task's source file, retargeting automatically when it has moved.
def heal-source []: record -> path {
  let task: record = $in
  if ($task.source.path | path exists) { return $task.source.path }
  let root: directory = $task.project.path | default $PROJECTS
  let hits: list = glob --no-dir ($root | path join ** ($task.source.path | path basename))
  match ($hits | length) {
    1 => {
      # Direct stor update: routing through update-tasks would re-enter sync.
      stor update --table-name $DB.name --update-record {
        source: ($task.source | update path $hits.0?)
      } --where-clause $"id = '($task.id | sql-str)'"
      $hits.0?
    }
    0 => {
      error make --unspanned $"source file for '($task.id)' is missing \(($task.source.path)); relink it with `tasks retarget`"
    }
    _ => {
      error make --unspanned $"multiple source candidates for '($task.id)': ($hits | str join ', '); relink it with `tasks retarget`"
    }
  }
}

def query-tasks [
  --set: string
  --select: string
  --where: string
]: nothing -> table {
  let q: string = if $set != null {
    [UPDATE $DB.name SET $set]
  } else if $select != null {
    [SELECT $select FROM $DB.name]
  } | if ($where | is-empty) { } else { append [WHERE $where] }
    | str join (char space)
  stor open | query db $q
}

def subtask-default []: [
  table<synopsis: string> -> table<synopsis: string, done: bool, llm: string>
  record<synopsis: string> -> record<synopsis: string, done: bool, llm: string>
] { default false done | default none llm }

# The loose `record` input is deliberate: a legacy row's subtasks can be SQL
# NULL, which the stricter record<subtasks: record> rejects before the body's
# `default {}` can absorb it.
def subtask-hydrate []: [
  record -> table<index: int, item: record<synopsis: string, done: bool, llm: string>>
] {
  get subtasks | default {} | items {|n st|
    $n | into int | wrap index | insert item { $st | subtask-default }
  }
}

# Pack an ordered list of subtasks back into the stored {<index>: <subtask>} shape.
def subtask-pack []: list -> record {
  subtask-default
  | enumerate
  # ponytail: wrap requires a string column name and a runtime int fails it,
  # so we convert index to a string before wrapping
  | update index { into string }
  | each {|it| get item | wrap $it.index }
  | into record
}

# Escape single quotes for safe embedding in a SQL string literal.
def sql-str []: string -> string {
  str replace --all "'" "''"
}

## Completions

def _project-names []: nothing -> list<directory> {
  cd $PROJECTS
  glob * --no-file --no-symlink | path basename
}

def _task-ids []: nothing -> list<string> {
  # --sync=false: completions stay snappy.
  ensure-db --sync=false
  query-tasks --select 'DISTINCT id' | get id
}

def _db-fields []: nothing -> list<string> {
  ensure-db --sync=false
  # Offer the subtask indices present in live data; leaf fields chain
  # manually, e.g. subtasks->>'1'->>'done'.
  $DB.columns | columns
  | append [
    `project->>'name'`
    `project->>'path'`
    `source->>'path'`
    ...(
      stor open
      | query db $"SELECT DISTINCT json_each.key AS k FROM ($DB.name), json_each\(subtasks)"
      | each { $"subtasks->>'($in.k)'" }
    )
  ]
}

# Write-back sync: CLI changes land in the source file, and only there.
use ../mod.nu *

def "test done-syncs-to-file" []: nothing -> nothing {
  with-sandbox {|ctx|
    let p = stage-project $ctx
    tasks-run $ctx $"tasks import ($p.file | to nuon); tasks sub alpha --done 0" | unwrap
    let entry = open $p.file | get tasks."0"
    assert equal ($entry.subtasks | get done) [true false]
  }
}

def "test splice-preserves-document-head" []: nothing -> nothing {
  with-sandbox {|ctx|
    let p = stage-project $ctx
    let before: list<string> = head-lines $p.file
    tasks-run $ctx $"tasks import ($p.file | to nuon); tasks sub alpha --done 0" | unwrap
    assert equal (head-lines $p.file) $before
    assert str contains (open --raw $p.file) '# hand comment survives'
    assert str contains (open --raw $p.file) 'date   = 2026-07-09'
  }
}

def "test all-done-stamps-completed-as-localdate" []: nothing -> nothing {
  with-sandbox {|ctx|
    let p = stage-project $ctx
    tasks-run $ctx $"tasks import ($p.file | to nuon); tasks sub alpha --done 0; tasks sub alpha --done 1" | unwrap
    let completed = tasks-run $ctx 'tasks list --id alpha --field completed | get 0.completed | print' | unwrap
    assert ($completed =~ '^\d{4}-\d{2}-\d{2}$')
    # The schema types completed as a TOML LocalDate: unquoted in the file.
    assert ((open --raw $p.file) =~ 'completed = \d{4}-\d{2}-\d{2}')
  }
}

def "test noop-refresh-keeps-mtime" []: nothing -> nothing {
  with-sandbox {|ctx|
    let p = stage-project $ctx
    tasks-run $ctx $"tasks import ($p.file | to nuon); tasks sub alpha --done 0" | unwrap
    let before = ls $p.file | get 0.modified
    sleep 1.1sec
    tasks-run $ctx 'tasks list' | unwrap
    tasks-run $ctx 'tasks list' | unwrap
    assert equal (ls $p.file | get 0.modified) $before
  }
}

def "test json-source-roundtrip" []: nothing -> nothing {
  with-sandbox {|ctx|
    let p = stage-project $ctx
    tasks-run $ctx $"tasks import ($p.json | to nuon); tasks sub json-one --done 0" | unwrap
    let doc = open $p.json
    assert equal $doc.tasks."0".subtasks.0.done true
    assert ($doc.tasks."0".completed =~ '^\d{4}-\d{2}-\d{2}$')
  }
}

def "test tombi-flags-schema-violations" []: nothing -> nothing {
  if (which tombi | is-empty) { skip 'tombi not installed' }
  with-sandbox {|ctx|
    let p = stage-project $ctx
    tasks-run $ctx $"tasks import ($p.file | to nuon)" | unwrap
    let silent = tasks-run $ctx 'tasks sub alpha --set {0: {llm: bananas}} --check=false'
    assert equal ($silent.stderr | str trim) ''
    let flagged = tasks-run $ctx 'tasks sub alpha --set {1: {llm: automation}}'
    assert str contains $flagged.stderr 'tombi lint'
  }
}

def "test del-removes-file-entry" []: nothing -> nothing {
  with-sandbox {|ctx|
    let p = stage-project $ctx
    tasks-run $ctx $"tasks import ($p.file | to nuon); tasks del --id beta" | unwrap
    assert equal (open $p.file | get tasks | columns) ["0"]
    # Nothing left behind to resurrect from on the next refresh.
    let ids = tasks-run $ctx 'tasks list | get id | to nuon | print' | unwrap | from nuon
    assert equal $ids [alpha]
  }
}

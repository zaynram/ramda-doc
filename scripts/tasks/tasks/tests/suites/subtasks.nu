# Subtask CRUD on native (unsourced) tasks. The in-memory database does not
# persist mutations across interpreters without a source file, so every test
# runs its whole scenario in one child.
use ../mod.nu *

def "test add-seeds-summary-counts" []: nothing -> nothing {
  with-sandbox {|ctx|
    let rows = tasks-run $ctx 'tasks add t --subtasks [[synopsis]; [a] [b]]; tasks | select id total done | to nuon | print'
      | unwrap | from nuon
    assert equal $rows [[id total done]; [t 2 0]]
  }
}

def "test sub-add-appends-with-defaults" []: nothing -> nothing {
  with-sandbox {|ctx|
    let rows = tasks-run $ctx 'tasks add t --subtasks [[synopsis]; [one]]; tasks sub t --add {synopsis: extra} | select synopsis done llm | to nuon | print'
      | unwrap | from nuon
    assert equal $rows [[synopsis done llm]; [one false none] [extra false none]]
  }
}

def "test sub-index-inserts-and-shifts" []: nothing -> nothing {
  with-sandbox {|ctx|
    let names = tasks-run $ctx 'tasks add t --subtasks [[synopsis]; [one] [three]]; tasks sub t --index {1: {synopsis: two}} | get synopsis | to nuon | print'
      | unwrap | from nuon
    assert equal $names [one two three]
  }
}

def "test sub-set-merges-partial-fields" []: nothing -> nothing {
  with-sandbox {|ctx|
    let rows = tasks-run $ctx 'tasks add t --subtasks [[synopsis]; [one] [two]]; tasks sub t --set {0: {done: true}} | select synopsis done | to nuon | print'
      | unwrap | from nuon
    assert equal $rows [[synopsis done]; [one true] [two false]]
  }
}

def "test sub-done-marks-one-index" []: nothing -> nothing {
  with-sandbox {|ctx|
    let flags = tasks-run $ctx 'tasks add t --subtasks [[synopsis]; [one] [two]]; tasks sub t --done 1 | get done | to nuon | print'
      | unwrap | from nuon
    assert equal $flags [false true]
  }
}

def "test sub-pop-drops-and-shifts" []: nothing -> nothing {
  with-sandbox {|ctx|
    let names = tasks-run $ctx 'tasks add t --subtasks [[synopsis]; [one] [two]]; tasks sub t --pop 0 | get synopsis | to nuon | print'
      | unwrap | from nuon
    assert equal $names [two]
  }
}

def "test all-done-stamps-native-task" []: nothing -> nothing {
  with-sandbox {|ctx|
    let stamp = tasks-run $ctx 'tasks add t --subtasks [[synopsis]; [solo]]; tasks sub t --done 0 | ignore; tasks list --sync=false --field completed | get 0.completed | print'
      | unwrap
    assert ($stamp =~ '^\d{4}-\d{2}-\d{2}$')
  }
}

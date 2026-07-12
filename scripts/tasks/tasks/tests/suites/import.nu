# Importing issue files: the file is the source of truth.
use ../mod.nu *

def "test import-returns-rows" []: nothing -> nothing {
  with-sandbox {|ctx|
    let p = stage-project $ctx
    let rows = tasks-run $ctx $"tasks import ($p.file | to nuon) | select id completed | to nuon | print"
      | unwrap | from nuon
    assert equal $rows [[id completed]; [alpha null] [beta null]]
  }
}

def "test import-is-idempotent" []: nothing -> nothing {
  with-sandbox {|ctx|
    let p = stage-project $ctx
    tasks-run $ctx $"tasks import ($p.file | to nuon)" | unwrap
    let before: string = open --raw $p.file
    tasks-run $ctx $"tasks import ($p.file | to nuon)" | unwrap
    assert equal (open --raw $p.file) $before
  }
}

def "test refresh-prunes-vanished-entries" []: nothing -> nothing {
  with-sandbox {|ctx|
    let p = stage-project $ctx
    tasks-run $ctx $"tasks import ($p.file | to nuon)" | unwrap
    # A hand edit removes beta; a mere list must prune its row.
    open --raw $p.file
    | str replace --regex '(?s)  1 = \{.*' ''
    | save --force --raw $p.file
    let ids = tasks-run $ctx 'tasks list | get id | to nuon | print' | unwrap | from nuon
    assert equal $ids [alpha]
  }
}

def "test refresh-pulls-file-edits" []: nothing -> nothing {
  with-sandbox {|ctx|
    let p = stage-project $ctx
    tasks-run $ctx $"tasks import ($p.file | to nuon)" | unwrap
    open --raw $p.file | str replace "synopsis = 'one'" "synopsis = 'one edited'" | save --force --raw $p.file
    let subs = tasks-run $ctx 'tasks sub alpha | get 0.synopsis | print' | unwrap
    assert equal $subs 'one edited'
  }
}

def "test sync-flag-opts-out-of-refresh" []: nothing -> nothing {
  with-sandbox {|ctx|
    let p = stage-project $ctx
    tasks-run $ctx $"tasks import ($p.file | to nuon)" | unwrap
    open --raw $p.file | str replace "synopsis = 'one'" "synopsis = 'one edited'" | save --force --raw $p.file
    let stale = tasks-run $ctx 'tasks sub alpha --sync=false | get 0.synopsis | print' | unwrap
    assert equal $stale 'one'
  }
}

def "test version-mismatch-warns-but-imports" []: nothing -> nothing {
  with-sandbox {|ctx|
    let p = stage-project $ctx
    open --raw $p.file | str replace "version = '3.0.0'" "version = '2.0.0'" | save --force --raw $p.file
    let out = tasks-run $ctx $"tasks import ($p.file | to nuon) | get id | to nuon | print"
    assert str contains $out.stderr 'declares schema 2.0.0'
    assert equal ($out | unwrap | from nuon) [alpha beta]
  }
}

def "test native-id-conflict-errors" []: nothing -> nothing {
  with-sandbox {|ctx|
    let p = stage-project $ctx
    tasks-run $ctx 'tasks add alpha' | unwrap
    let out = tasks-run $ctx $"tasks import ($p.file | to nuon)"
    assert ($out.exit_code != 0)
    assert str contains $out.stderr 'already exists without a source'
  }
}

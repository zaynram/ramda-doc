# Source-control integration: sync commits, branch routing, and undo
use ../mod.nu *

def "test sync-commits-with-summary" []: nothing -> nothing {
  with-sandbox {|ctx|
    let p = stage-project $ctx
    git-init $p.root
    tasks-run $ctx $"tasks import ($p.file | to nuon)" | unwrap
    # Importing alone changes nothing file-side: no commit.
    assert equal (git -C $p.root log -1 --format=%s | str trim) initial
    tasks-run $ctx 'tasks sub alpha --done 0' | unwrap
    assert equal (git -C $p.root log -1 --format=%s | str trim) 'tasks: sync thing.issue.toml'
    assert str contains (git -C $p.root log -1 --format=%b) '~ alpha: subtasks'
    # Pathspec-scoped: the sync leaves nothing dirty and sweeps nothing else in.
    assert equal (git -C $p.root status --porcelain | str trim) ''
  }
}

def "test commit-opt-out-leaves-dirty" []: nothing -> nothing {
  with-sandbox {|ctx|
    let p = stage-project $ctx
    git-init $p.root
    tasks-run $ctx $"tasks import ($p.file | to nuon); tasks sub alpha --done 0 --commit=false" | unwrap
    assert equal (^git -C $p.root log -1 --format=%s | str trim) initial
    assert str contains (^git -C $p.root status --porcelain) docs/thing.issue.toml
  }
}

def "test routes-to-declared-branch" []: nothing -> nothing {
  with-sandbox {|ctx|
    let p = stage-project $ctx --reference feat/thing
    git-init $p.root --branches [feat/thing]
    tasks-run $ctx $"tasks import ($p.file | to nuon); tasks sub alpha --done 0" | unwrap
    assert equal (git -C $p.root log -1 --format=%s feat/thing | str trim) 'tasks: sync thing.issue.toml'
    assert equal (^git -C $p.root log -1 --format=%s main | str trim) initial
    # The synced content is staged in the current checkout too, so reaching
    # the issue branch is one clean checkout — no stash dance.
    let checkout = do { ^git -C $p.root checkout --quiet feat/thing } | complete
    assert equal $checkout.exit_code 0
    assert equal (git -C $p.root status --porcelain | str trim) ''
  }
}

def "test missing-branch-warns-and-leaves-uncommitted" []: nothing -> nothing {
  with-sandbox {|ctx|
    let p = stage-project $ctx --reference feat/ghost
    git-init $p.root
    let out = tasks-run $ctx $"tasks import ($p.file | to nuon); tasks sub alpha --done 0"
    assert equal $out.exit_code 0
    assert str contains $out.stderr 'could not commit the sync'
    assert equal (^git -C $p.root log -1 --format=%s | str trim) initial
    # The change itself still landed: only the commit was refused.
    assert equal (open $p.file | get -o tasks."0".subtasks.0.done) true
  }
}

def "test undo-reverts-last-sync" []: nothing -> nothing {
  with-sandbox {|ctx|
    let p = stage-project $ctx
    git-init $p.root
    tasks-run $ctx $"tasks import ($p.file | to nuon); tasks sub alpha --done 0" | unwrap
    tasks-run $ctx 'tasks undo alpha' | unwrap
    assert equal (open $p.file | get -o tasks."0".subtasks.0.done) false
    assert equal (git -C $p.root log -1 --format=%s | str trim) 'tasks: undo thing.issue.toml'
    assert str contains (git -C $p.root log -1 --format=%b) 'This reverts'
    # The revert re-imported: the database mirrors the restored file.
    let done = tasks-run $ctx 'tasks sub alpha --sync=false | get 0.done | print' | unwrap
    assert equal $done 'false'
  }
}

def "test undo-of-undo-redoes" []: nothing -> nothing {
  with-sandbox {|ctx|
    let p = stage-project $ctx
    git-init $p.root
    tasks-run $ctx $"tasks import ($p.file | to nuon); tasks sub alpha --done 0" | unwrap
    tasks-run $ctx 'tasks undo alpha | ignore; tasks undo alpha' | unwrap
    assert equal (open $p.file | get -o tasks."0".subtasks.0.done) true
  }
}

def "test undo-refuses-manual-history" []: nothing -> nothing {
  with-sandbox {|ctx|
    let p = stage-project $ctx
    git-init $p.root
    tasks-run $ctx $"tasks import ($p.file | to nuon); tasks sub alpha --done 0" | unwrap
    $"(open --raw $p.file)\n# manual note\n" | save --force --raw $p.file
    ^git -C $p.root add --all
    ^git -C $p.root commit --quiet --message 'manual edit'
    let out = tasks-run $ctx 'tasks undo alpha'
    assert ($out.exit_code != 0)
    assert str contains $out.stderr 'non-sync commits'
  }
}

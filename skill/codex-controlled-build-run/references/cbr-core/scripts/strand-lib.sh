#!/usr/bin/env bash
# strand-lib.sh — the shared, provider-neutral mechanics of a strand's death
# ritual. Part of `cbr-core`: the law that these steps HAPPEN is step 9 of
# `build-loop.md` ("The three duties closeout owes the base branch"); this file
# is the pure-git machinery that performs them, so both harness leaves run the
# SAME mechanism instead of two drifting copies of it — which is what that law
# asks for, and for the reason it gives: the drift is invisible because the
# failure shows up in the NEXT strand, not this one.
#
# Neutrality: nothing here knows a vendor, a session registry, a transcript
# format, or a launch command — those stay in the leaf that owns them. Every
# function below is git, the filesystem, and the process table.
#
# Sourced, not executed:
#
#     . "<...>/cbr-core/scripts/strand-lib.sh"
#
# Contract shared by every function: they report on stdout as `key=value` and
# return 0 for every state the caller can legitimately meet (a record the
# strand never wrote, a marker that was already gone, a plan that does not
# exist). A non-zero return means the work could not be done: an unreadable
# repository, a missing argument, or a record that exists and could not be
# saved. It never means "nothing to do". The
# predicates (`cbr_branch_is_merged`, `cbr_marker_is_foreign`,
# `cbr_path_has_live_process`) are the deliberate exception: they answer a
# yes/no question with their exit status and print nothing.

# ---------------------------------------------------------------------------
# cbr_record_files_default — the strand records worth keeping, in the order a
# reader wants them. A port appends its own repo-specific blocker filenames;
# these are the ones every CBR strand has.
# ---------------------------------------------------------------------------
cbr_record_files_default() {
  cat <<'EOF'
task_plan.md
progress.md
findings.md
STATUS.md
DONE.marker
ASK-ORCH.md
ORCH-ANSWER.md
KNOWN-LIMITATIONS.md
EOF
}

# ===========================================================================
# BIRTH DUTIES — what provision owes a newborn strand. Mirrors the death
# duties below: the same reasoning (leftovers from one strand poisoning the
# next, drift between leaves) applies at both ends of a strand's life.
# ===========================================================================

# ---------------------------------------------------------------------------
# cbr_provision_reset_stale_records WORKTREE
#
# Remove the record files a fresh worktree INHERITS from its base. A strand's
# records are per-strand by definition, yet the base branch can carry a dead
# strand's STATUS.md ("phase: COMPLETE"), DONE.marker, or an old ASK/ANSWER
# pair — and a watcher glancing at the inherited copy believes a build that
# never ran. The plan and the logs are NOT touched: task_plan.md is dropped
# in (or skeleton'd) after provision and gate-checked for coherence, and the
# leaves already reset progress.md/findings.md with their own headers.
# Reports removed=N; fails only when a removal could not be done (including a
# directory squatting on a record name — never deleted blind).
# ---------------------------------------------------------------------------
cbr_provision_reset_stale_records() {
  local wt="${1:?worktree required}"
  [ -d "$wt" ] || { echo "strand-lib: worktree '$wt' does not exist" >&2; return 1; }
  local n=0 rc=0 f
  for f in STATUS.md DONE.marker ASK-ORCH.md ORCH-ANSWER.md KNOWN-LIMITATIONS.md; do
    if [ -e "$wt/$f" ] || [ -L "$wt/$f" ]; then
      if [ -d "$wt/$f" ] && [ ! -L "$wt/$f" ]; then
        echo "strand-lib: inherited $wt/$f is a directory, not a record — clear it by hand" >&2
        rc=1
      elif rm -f "$wt/$f"; then
        echo "stale_record_removed=$f"
        n=$((n+1))
      else
        echo "strand-lib: inherited $wt/$f could not be removed" >&2
        rc=1
      fi
    fi
  done
  echo "removed=$n"
  return "$rc"
}

# ---------------------------------------------------------------------------
# cbr_record_strand_base REPO BRANCH BASE
# cbr_assert_strand_base REPO BRANCH
#
# Write the strand's declared base down at birth (as a resolved commit, in
# git config under the branch — it survives worktree moves and needs no file
# in anyone's tree), so that launch can mechanically prove the branch still
# grows from it: `merge-base --is-ancestor` — the check that turns a silent
# wrong-base fork into a loud pre-dispatch failure.
#
# Assert returns: 0 = pinned base is in the branch's history; 1 = it is NOT
# (refuse to dispatch); 2 = no pin was ever recorded (a strand born before
# this law) — the caller warns and proceeds, it does not brick old strands.
# ---------------------------------------------------------------------------
cbr_record_strand_base() {
  local repo="${1:?repo required}" branch="${2:?branch required}" base="${3:?base ref required}"
  local sha
  sha="$(git -C "$repo" rev-parse -q --verify "$base^{commit}" 2>/dev/null)" \
    || { echo "strand-lib: base ref '$base' does not resolve" >&2; return 1; }
  git -C "$repo" config "branch.$branch.cbrBase" "$sha" \
    || { echo "strand-lib: could not record base pin for '$branch'" >&2; return 1; }
  echo "base_pin=$sha"
}

cbr_assert_strand_base() {
  local repo="${1:?repo required}" branch="${2:?branch required}"
  local pin
  pin="$(git -C "$repo" config --get "branch.$branch.cbrBase" 2>/dev/null)" || pin=""
  [ -n "$pin" ] || { echo "base_pin=unknown"; return 2; }
  if git -C "$repo" merge-base --is-ancestor "$pin" "$branch" 2>/dev/null; then
    echo "base_pin=$pin base_pin_ok=1"
    return 0
  fi
  echo "strand-lib: branch '$branch' does not contain its recorded base $pin — it grew from the wrong place, or the pin is stale; refuse to dispatch onto it" >&2
  return 1
}

# ---------------------------------------------------------------------------
# cbr_run_provision_hook REPO WORKTREE
#
# The project prep-hook socket. Stack-specific workspace prep (dependency
# links, venv wiring) can never live in this neutral core, and baking it into
# a leaf makes the leaf non-portable — so the core owns only the SOCKET:
# if the project defines `.cbr/provision-hook.sh` at its primary root, run it
# with the worktree as cwd and (REPO, WORKTREE) as arguments. Absent hook is
# the normal case and a clean skip. A present-but-non-executable hook is a
# misconfiguration and fails loudly. A failing hook fails the provision —
# a half-prepared worktree is exactly the trap this socket exists to remove.
# ---------------------------------------------------------------------------
cbr_run_provision_hook() {
  local repo="${1:?repo required}" wt="${2:?worktree required}"
  local hook="$repo/.cbr/provision-hook.sh"
  if [ ! -e "$hook" ]; then
    echo "hook=absent"
    return 0
  fi
  [ -x "$hook" ] || { echo "strand-lib: $hook exists but is not executable — chmod +x it (a hook that silently never runs is worse than none)" >&2; return 1; }
  if ( cd "$wt" && "$hook" "$repo" "$wt" ); then
    echo "hook=ran"
    return 0
  fi
  echo "strand-lib: provision hook failed — the worktree is half-prepared; fix the hook before dispatch" >&2
  return 1
}

# ---------------------------------------------------------------------------
# cbr_strand_fork_point REPO STRAND BASE — print the commit the strand grew
# from.
#
# After the strand has merged, `merge-base STRAND BASE` is the strand's own tip
# — useless for asking "what did this strand inherit". Hunting for the merge
# commit is no better: record-only commits after a merge, or a SECOND merge of
# the same strand, leave no single merge whose parents recover the original
# fork (RoboRev 3785, 3792). The definition that survives all of that is
# structural: walk the strand's own first-parent chain backwards; the first
# commit that sits on the BASE's first-parent chain is where the strand grew
# from. Integrations of the strand live on the base's chain, so however many
# there are they never shadow the walk, and update-merges FROM the base into
# the strand hang off second parents, so they don't either. Prints nothing and
# returns non-zero when no fork point can be established — the caller treats
# that as "unknown", never as "the strand owns everything" or "owns nothing".
# ---------------------------------------------------------------------------
cbr_strand_fork_point() {
  local repo="${1:?repo required}" strand="${2:?strand ref required}" base="${3:?base ref required}"
  local tip c base_chain
  tip="$(git -C "$repo" rev-parse -q --verify "$strand^{commit}" 2>/dev/null)" || return 1
  # Complete chains, no depth cap: a capped walk that misses would need a
  # fallback, and every fallback that can name a WRONG commit (merge-base of
  # a merged strand names its own merged tip) shrinks the archive silently
  # (RoboRev 3795). Full first-parent lists are cheap at any history this
  # harness will meet, and a genuine miss — disjoint histories — returns
  # failure, which the caller reads as "unknown" and archives unfiltered.
  base_chain="$(git -C "$repo" rev-list --first-parent "$base" 2>/dev/null)" || return 1
  [ -n "$base_chain" ] || return 1
  for c in $(git -C "$repo" rev-list --first-parent "$tip" 2>/dev/null); do
    case "$base_chain" in
      *"$c"*) printf '%s\n' "$c"; return 0 ;;
    esac
  done
  return 1
}

# ---------------------------------------------------------------------------
# cbr_archive_strand_records REPO REF DEST FILE...
#
# Copy each record file OUT OF THE STRAND'S FINAL COMMIT into DEST.
#
# Reading the commit rather than the worktree is the whole point. By the time
# closeout runs, the strand has merged, so the base checkout holds the same
# bytes — a copier that skips files matching the base's copy therefore skips
# the entire archive, and one that reads the worktree loses anything the merge
# or a later commit changed. The commit is the only source that still holds
# what the strand actually ended with, and it survives the worktree being
# deleted seconds later.
#
# Prints `archived=<n>`. A record the strand never wrote is absent from the
# archive rather than present-and-empty: an empty archived plan reads as "the
# builder wrote nothing", which is a lie about a strand that simply had no
# STATUS.md.
#
# `CBR_ARCHIVE_FORK` (a commit) narrows "wrote" to the strand's OWN work: a
# candidate whose blob is byte-identical at the fork point was inherited from
# the base, not authored here, and archiving it stamps another run's paperwork
# with this strand's name (RoboRev 3782 caught exactly that in two real
# archives). Identical-at-fork is therefore skipped like the absent case.
# Unset, or naming the ref itself (a strand with no commits of its own has no
# inherited/authored distinction to draw), the filter stays out of the way —
# provenance uncertainty must widen the archive, never silently shrink it.
#
# A record that EXISTS but cannot be written is a different animal, and it
# returns non-zero. Closeout deletes the worktree and the branch moments later,
# so this is the last instant the record exists anywhere; reporting success
# over a lost one would rebuild, inside the fix, the very class of silent loss
# the fix exists to remove.
# ---------------------------------------------------------------------------
cbr_archive_strand_records() {
  local repo="${1:?repo required}" ref="${2:?ref required}" dest="${3:?dest required}"
  shift 3
  [ "$#" -gt 0 ] || set -- $(cbr_record_files_default)

  git -C "$repo" rev-parse --git-dir >/dev/null 2>&1 || {
    echo "strand-lib: not a git repository: $repo" >&2
    return 2
  }
  git -C "$repo" rev-parse -q --verify "$ref" >/dev/null 2>&1 || {
    echo "strand-lib: no such ref: $ref" >&2
    return 2
  }

  cbr_archive_dest_is_contained "$repo" "$dest" || {
    echo "strand-lib: archive destination is not a real path inside $repo: $dest" >&2
    return 2
  }
  mkdir -p "$dest" || return 2
  cbr_archive_stamp "$dest" "$repo" "$ref" || {
    echo "strand-lib: could not stamp $dest with the strand it belongs to" >&2
    return 2
  }

  local fork=""
  if [ -n "${CBR_ARCHIVE_FORK:-}" ]; then
    fork="$(git -C "$repo" rev-parse -q --verify "${CBR_ARCHIVE_FORK}^{commit}" 2>/dev/null)" || fork=""
    [ "$fork" = "$(git -C "$repo" rev-parse -q --verify "$ref^{commit}" 2>/dev/null)" ] && fork=""
  fi

  local n=0 f rc=0 probe entry part ref_blob fork_blob
  for f in "$@"; do
    [ -n "$f" ] || continue
    # "Is this path in that tree" must be answerable WITHOUT conflating two very
    # different answers: a record the strand never wrote, and a repository git
    # cannot read. `cat-file -e` cannot tell them apart — it exits 128 for both —
    # so the absent case would swallow the unreadable one and report a successful
    # archive of nothing. `ls-tree` separates them cleanly: a non-zero exit is a
    # failure to look, and empty output is having looked and found nothing.
    probe=0
    entry="$(git -C "$repo" ls-tree "$ref" -- "$f" 2>/dev/null)" || probe=$?
    if [ "$probe" -ne 0 ]; then
      echo "strand-lib: git could not inspect $ref:$f in $repo (exit $probe)" >&2
      rc=1
      continue
    fi
    if [ -z "$entry" ]; then
      # The strand never wrote this record. If a slot for it is sitting in the
      # destination anyway, it is debris from an earlier attempt or an earlier
      # strand, and leaving it would make the archive a blend of two runs while
      # `archived=` reports only this one. The archive is a picture of ONE final
      # commit or it is worthless as evidence.
      # `-e` alone misses a DANGLING symlink, which is exactly the kind of
      # debris an interrupted run leaves; `-L` catches it. A directory in a
      # record slot is not something to delete on a strand's behalf — it fails
      # closed for a human to look at.
      if [ -e "$dest/$f" ] || [ -L "$dest/$f" ]; then
        if [ -d "$dest/$f" ] && [ ! -L "$dest/$f" ]; then
          echo "strand-lib: stale $dest/$f is a directory, not a record — clear it by hand" >&2
          rc=1
        elif ! rm -f "$dest/$f"; then
          echo "strand-lib: stale $dest/$f could not be cleared" >&2
          rc=1
        fi
      fi
      continue
    fi
    case "$entry" in
      *' blob '*) ;;
      *) echo "strand-lib: $ref:$f is not a file in that tree" >&2; rc=1; continue ;;
    esac

    # Inherited, not authored: identical bytes at the fork point mean the strand
    # carried this record, it did not write it — and a stale copy already at the
    # destination is the same cross-run debris the absent case clears.
    if [ -n "$fork" ]; then
      ref_blob="$(git -C "$repo" rev-parse -q --verify "$ref:$f" 2>/dev/null)" || ref_blob=""
      fork_blob="$(git -C "$repo" rev-parse -q --verify "$fork:$f" 2>/dev/null)" || fork_blob=""
      if [ -n "$ref_blob" ] && [ "$ref_blob" = "$fork_blob" ]; then
        if [ -e "$dest/$f" ] || [ -L "$dest/$f" ]; then
          if [ -d "$dest/$f" ] && [ ! -L "$dest/$f" ]; then
            echo "strand-lib: stale $dest/$f is a directory, not a record — clear it by hand" >&2
            rc=1
          elif ! rm -f "$dest/$f"; then
            echo "strand-lib: stale $dest/$f could not be cleared" >&2
            rc=1
          fi
        fi
        continue
      fi
    fi

    # A destination that is a DIRECTORY would swallow the rename below — mv puts
    # the file INSIDE it and reports success, leaving the archive path still a
    # directory while the count claims a saved record.
    if [ -d "$dest/$f" ]; then
      echo "strand-lib: archive destination $dest/$f is a directory, not a record slot" >&2
      rc=1
      continue
    fi

    # Write via a temp file: a `show` that dies mid-stream would otherwise leave
    # a truncated record in the archive, which is worse than no record at all.
    # The count moves only after the rename lands AND the result is a regular
    # file, so `archived=` never claims a record that is not sitting there.
    if ! part="$(cbr_archive_tempfile "$dest")"; then
      echo "strand-lib: could not create a temp slot in $dest" >&2
      rc=1
      continue
    fi
    if ! git -C "$repo" show "$ref:$f" > "$part" 2>/dev/null; then
      rm -f "$part"
      echo "strand-lib: could not read $ref:$f out of $repo" >&2
      rc=1
      continue
    fi
    # `-f` FOLLOWS symlinks, so it would call a symlink-to-a-file an archived
    # record. The archive must hold the bytes, not a pointer to them.
    if ! mv -f "$part" "$dest/$f" || [ -L "$dest/$f" ] || [ ! -f "$dest/$f" ]; then
      rm -f "$part"
      echo "strand-lib: could not write $dest/$f" >&2
      rc=1
      continue
    fi
    n=$((n + 1))
  done
  echo "archived=$n"
  return "$rc"
}

# ---------------------------------------------------------------------------
# cbr_archive_dest_is_contained REPO DEST   (exit 0 = safe to write into)
#
# Every write into an archive must land inside the repository, at the path the
# closeout was actually given. Guarding the destination alone is not enough and
# it took several rounds to accept that: a symlink ANYWHERE above it — or a `..`
# in the middle — redirects `mkdir`, `mktemp` and `mv` alike, and the closeout
# then stages a directory holding none of the bytes it wrote.
#
# So this asks one question instead of guarding one path at a time. Resolve the
# nearest ancestor that actually exists, physically, and require it to be the
# same path lexically. A symlinked ancestor resolves elsewhere and fails; a `..`
# normalizes away and fails; a destination outside the repository fails before
# any of that. Components that do not exist yet cannot be symlinks, so there is
# nothing below the nearest existing ancestor to check.
# ---------------------------------------------------------------------------
cbr_archive_dest_is_contained() {
  local repo="${1:?repo required}" dest="${2:?dest required}"
  local repo_phys anc anc_phys rel

  repo_phys="$(cd "$repo" 2>/dev/null && pwd -P)" || return 1
  case "$dest" in
    /*) ;;
    *) return 1 ;;          # a relative destination has no anchor to check
  esac
  case "$dest" in
    "$repo_phys"/*) ;;
    *) return 1 ;;
  esac

  anc="$dest"
  while [ ! -e "$anc" ] && [ "$anc" != "/" ]; do
    anc="$(dirname "$anc")"
  done
  if [ -L "$anc" ] || [ ! -d "$anc" ]; then return 1; fi

  anc_phys="$(cd "$anc" 2>/dev/null && pwd -P)" || return 1
  [ "$anc_phys" = "$anc" ]
}

# ---------------------------------------------------------------------------
# CBR_ARCHIVE_STAMP — the file inside an archive that says which strand it is
# ---------------------------------------------------------------------------
CBR_ARCHIVE_STAMP=".cbr-archive-of"

# ---------------------------------------------------------------------------
# cbr_archive_is_retry_of ARCHIVE REPO REF
#
# Exit 0 only when the archive directory can be PROVEN to be an interrupted
# attempt at archiving THIS run — safe to write over.
#
# Provenance is the strand's final COMMIT, not its name. Names are reused:
# slugs come back, and `stream/<slug>` with them, so a matching branch name is
# equally consistent with "my own failed attempt ten seconds ago" and "the
# permanent record of a strand that used this slug in March". A commit sha
# separates those two, and nothing weaker does.
#
# Anything unprovable — no stamp, an unreadable one, a directory that is really
# a symlink — is NOT a retry. The cost of a false yes is overwriting the only
# copy of a finished strand's records; the cost of a false no is one `mv` by a
# human who can see what is there.
# ---------------------------------------------------------------------------
cbr_archive_is_retry_of() {
  local archive="${1:?archive required}" repo="${2:?repo required}" ref="${3:?ref required}"
  local stamped="" now=""

  # A symlink is never the archive: following one lets a closeout write records
  # outside the path it was told to write to, and then stage a directory that
  # holds none of them.
  # `[ -L x ] && return 1` is an AND-list that fails when x is not a symlink,
  # which under `set -e` is only survivable because every caller happens to use
  # it as a condition. Written as an `if`, it does not depend on that luck.
  if [ -L "$archive" ]; then return 1; fi
  [ -d "$archive" ] || return 1

  # A symlinked stamp is followed both when read and when rewritten, which turns
  # "prove this archive is mine" into "read a file of the attacker's choosing"
  # and the stamp write into a clobber outside the archive.
  if [ -L "$archive/$CBR_ARCHIVE_STAMP" ]; then return 1; fi
  [ -f "$archive/$CBR_ARCHIVE_STAMP" ] || return 1
  stamped="$(head -1 "$archive/$CBR_ARCHIVE_STAMP" 2>/dev/null | tr -d '[:space:]')" || return 1
  [ -n "$stamped" ] || return 1

  now="$(git -C "$repo" rev-parse -q --verify "$ref^{commit}" 2>/dev/null)" || return 1
  [ -n "$now" ] || return 1
  [ "$stamped" = "$now" ]
}

# ---------------------------------------------------------------------------
# cbr_archive_stamp ARCHIVE REPO REF — record whose archive this is.
#
# Written immediately after the directory is created, BEFORE any record goes in,
# so that an attempt which dies partway through still leaves behind an archive
# that can identify itself. A stamp written at the end would be missing from
# exactly the archives that need to prove they are retries.
# ---------------------------------------------------------------------------
cbr_archive_stamp() {
  local archive="${1:?archive required}" repo="${2:?repo required}" ref="${3:?ref required}" sha tmp
  sha="$(git -C "$repo" rev-parse -q --verify "$ref^{commit}" 2>/dev/null)" || return 1
  [ -n "$sha" ] || return 1

  # Never redirect straight onto the stamp path: if what sits there is a symlink,
  # the write lands wherever it points. Write a fresh regular file and rename it
  # over whatever is there, which replaces a symlink rather than following it.
  tmp="$(cbr_archive_tempfile "$archive")" || return 1
  printf '%s\n%s\n' "$sha" "$ref" > "$tmp" || { rm -f "$tmp"; return 1; }
  mv -f "$tmp" "$archive/$CBR_ARCHIVE_STAMP" || { rm -f "$tmp"; return 1; }
}

# ---------------------------------------------------------------------------
# cbr_archive_tempfile ARCHIVE — a freshly created regular file inside ARCHIVE.
#
# Every write into an archive goes through one of these and is then renamed into
# place. A redirect onto a predictable path — `$dest/$f.cbr-part`, the stamp —
# follows whatever symlink is sitting there, so debris left by an earlier run,
# or planted, becomes a write outside the archive. mktemp creates the file
# exclusively, so there is nothing to follow.
# ---------------------------------------------------------------------------
cbr_archive_tempfile() {
  local archive="${1:?archive required}" tmp
  tmp="$(mktemp "$archive/.cbr-part.XXXXXX" 2>/dev/null)" || return 1
  if [ -L "$tmp" ] || [ ! -f "$tmp" ]; then
    rm -f "$tmp"
    return 1
  fi
  printf '%s\n' "$tmp"
}

# ---------------------------------------------------------------------------
# cbr_archive_extra_record SRC ARCHIVE_DIR REPO REL_DIR
#
# Copy one record the shared duties know nothing about — a leaf-specific
# artefact such as a watch digest — into the archive, and stage it.
#
# It exists as a function rather than two lines in a leaf because of how those
# two lines fail. Written inline as `cp ... && stage ...`, a failure in either
# half is swallowed by the `&&`, and the reap that follows deletes the source:
# the record is lost and the closeout reports success. Here, either half failing
# returns non-zero, and the caller is left holding a strand it has not yet
# destroyed. Both failure paths are reachable from a test, which the inline form
# never was.
# ---------------------------------------------------------------------------
cbr_archive_extra_record() {
  local src="${1:?src required}" dir="${2:?archive dir required}"
  local repo="${3:?repo required}" rel="${4:?rel dir required}"
  local name

  [ -f "$src" ] || { echo "strand-lib: no such record to archive: $src" >&2; return 2; }
  name="$(basename "$src")"

  mkdir -p "$dir" || { echo "strand-lib: cannot create $dir" >&2; return 1; }
  # Through a temp file and a rename, like every other write into an archive:
  # a bare `cp` onto a name an earlier run left as a SYMLINK follows it and
  # writes outside the archive entirely.
  local part
  part="$(cbr_archive_tempfile "$dir")" || return 1
  if ! cat "$src" >"$part"; then
    rm -f "$part"
    echo "strand-lib: could not copy $src into $dir" >&2
    return 1
  fi
  if ! mv -f "$part" "$dir/$name"; then
    rm -f "$part"
    echo "strand-lib: could not place $name in $dir" >&2
    return 1
  fi
  if [ -L "$dir/$name" ] || [ ! -f "$dir/$name" ]; then
    echo "strand-lib: archived record $dir/$name is not a regular file" >&2
    return 1
  fi
  cbr_stage_paths "$repo" "$rel" >/dev/null || {
    echo "strand-lib: could not stage $rel after archiving $name" >&2
    return 1
  }
  echo "extra=$name"
}

# ---------------------------------------------------------------------------
# cbr_remove_marker_from_base REPO MARKER
#
# Delete the strand's completion marker from the base checkout and STAGE the
# deletion, so it rides the closeout commit.
#
# Why this is not housekeeping: the marker is merged onto the base along with
# the strand's work, and it stays there. The NEXT strand folds the base into
# its branch, inherits a marker that belongs to a strand that finished days
# ago, and its watcher latches on it — a completion signal for work that has
# not started. Observed live 2026-08-19.
#
# Prints `marker=removed`, `marker=removed-untracked`, or `marker=absent`.
# Absent is a normal outcome (closeout re-run, or the strand never wrote one),
# so it is not an error.
# ---------------------------------------------------------------------------
cbr_remove_marker_from_base() {
  local repo="${1:?repo required}" marker="${2:?marker path required}"
  git -C "$repo" rev-parse --git-dir >/dev/null 2>&1 || {
    echo "strand-lib: not a git repository: $repo" >&2
    return 2
  }

  if git -C "$repo" ls-files --error-unmatch -- "$marker" >/dev/null 2>&1; then
    git -C "$repo" rm -q --ignore-unmatch -- "$marker" || return 2
    echo "marker=removed"
    return 0
  fi
  # Untracked but present: still a live false signal to any watcher reading the
  # file, so it goes — there is just nothing to stage.
  if [ -e "$repo/$marker" ]; then
    rm -f "$repo/$marker" || return 2
    echo "marker=removed-untracked"
    return 0
  fi
  echo "marker=absent"
}

# ---------------------------------------------------------------------------
# cbr_reground_plan_branch PLAN BRANCH
#
# Point the plan's `**Branch:**` line back at BRANCH.
#
# A merged strand leaves the base's root plan naming a branch that no longer
# exists. The plan-coherence gate compares that line against the checked-out
# branch, so the base's very next commit fails until a human edits one line by
# hand — a recurring manual commit that closeout can simply do.
#
# Rewrites the branch TOKEN only, leaving any trailing text on the line intact,
# and touches no other line. Prints `reground=changed`, `reground=unchanged`,
# or `reground=absent`.
# ---------------------------------------------------------------------------
cbr_reground_plan_branch() {
  local plan="${1:?plan path required}" branch="${2:?branch required}"
  [ -f "$plan" ] || { echo "reground=absent"; return 0; }

  local current
  current="$(sed -nE 's/^\*\*Branch:\*\*[[:space:]]*([^[:space:]]+).*/\1/p' "$plan" | head -1)"
  if [ -z "$current" ]; then
    # No Branch line at all is not this function's business to invent: the plan
    # may predate the convention, and adding a line is an edit no caller asked
    # for. Report it as nothing-to-do and let the gate speak if it matters.
    echo "reground=absent"
    return 0
  fi
  [ "$current" = "$branch" ] && { echo "reground=unchanged"; return 0; }

  local tmp
  tmp="$(mktemp)" || return 2
  # awk, not sed -i: BSD and GNU sed disagree on -i's argument, and the
  # replacement text is a branch name that may contain characters sed would
  # read as delimiters or backreferences.
  awk -v want="$branch" '
    !done_it && /^\*\*Branch:\*\*[[:space:]]/ {
      # Split off the marker, the first token, and whatever trails it, then
      # re-emit with the token swapped; the trailing text belongs to the plan.
      rest = substr($0, length("**Branch:**") + 1)
      lead = ""
      while (substr(rest, 1, 1) == " " || substr(rest, 1, 1) == "\t") {
        lead = lead substr(rest, 1, 1); rest = substr(rest, 2)
      }
      tail = ""
      if (match(rest, /[[:space:]]/)) tail = substr(rest, RSTART)
      print "**Branch:**" lead want tail
      done_it = 1
      next
    }
    { print }
  ' "$plan" > "$tmp" || { rm -f "$tmp"; return 2; }
  cat "$tmp" > "$plan" || { rm -f "$tmp"; return 2; }   # preserve the file's mode/inode
  rm -f "$tmp"
  echo "reground=changed"
}

# ---------------------------------------------------------------------------
# cbr_marker_branch MARKER
#
# The branch a completion marker names on its first line, or nothing.
#
# The convention is `<branch> — COMPLETE <date>`, so the branch is the first
# token. "Or nothing" is load-bearing: markers written before the convention
# open with a slug or a title, and guessing a branch out of those would make
# every one of them look foreign to every watcher.
# ---------------------------------------------------------------------------
cbr_marker_branch() {
  local marker="${1:?marker path required}" token

  [ -f "$marker" ] || return 0

  # Take the first token of the first line, then let GIT say whether it is a
  # branch name. Approximating git's rules by hand does not fail safely here: a
  # name the approximation rejects is reported as "names nobody", which the
  # watchers read as "mine", and a name it wrongly accepts is reported as a
  # branch that will never match, which disarms completion for the whole run.
  # `check-ref-format` is the same rule git itself enforces, needs no
  # repository, and expands nothing (unlike `--branch`, which resolves @{-1}).
  token="$(head -1 "$marker" 2>/dev/null | awk '{ sub(/\r$/, ""); print $1; exit }')"
  [ -n "$token" ] || return 0

  # One slash minimum: `refs/heads/COMPLETE` is a perfectly valid ref, so
  # without this a marker headed by a bare word would be read as naming a
  # branch. Every strand branch in this process is `<kind>/<slug>`.
  case "$token" in
    */*) ;;
    *) return 0 ;;
  esac

  git check-ref-format "refs/heads/$token" 2>/dev/null || return 0
  printf '%s\n' "$token"
}

# ---------------------------------------------------------------------------
# cbr_marker_is_foreign MARKER BRANCH   (exit 0 = proven foreign)
#
# Does this marker belong to a DIFFERENT strand than BRANCH?
#
# Only a proven mismatch counts. A marker naming no branch, and a marker that
# does not exist, are both "not foreign" — the direction matters, because a
# false foreign verdict silently disables the completion signal, while a false
# native verdict merely leaves the pre-existing behaviour in place.
# ---------------------------------------------------------------------------
cbr_marker_is_foreign() {
  local marker="${1:?marker path required}" branch="${2:?branch required}" named
  named="$(cbr_marker_branch "$marker")"
  [ -n "$named" ] || return 1
  [ "$named" != "$branch" ]
}

# ---------------------------------------------------------------------------
# cbr_marker_counts_as_done MARKER BRANCH   (exit 0 = treat as this strand's completion)
#
# The question every watcher actually asks. A completion marker means "the build
# I am watching has finished" — and after a merge, the marker sitting in the
# worktree may belong to a strand that finished days ago, carried in on the base
# branch with its work.
#
# A watcher that latches on that marker exits, tells the human the build is done
# on the day it started, and leaves the builder unwatched for the rest of its
# run. So: the marker must exist, and it must not be provably somebody else's.
#
# Note the asymmetry, which is deliberate. Foreignness must be PROVEN — a marker
# naming no branch counts as ours, because markers predate the convention that
# they name one, and refusing those would quietly disarm the completion signal
# everywhere at once. A missed latch is loud (the watcher stalls, the stall
# fires, a human looks); a wrongly disarmed DONE is silent.
# ---------------------------------------------------------------------------
cbr_marker_counts_as_done() {
  local marker="${1:?marker path required}" branch="${2-}"
  [ -f "$marker" ] || return 1
  # An EMPTY branch is the detached-HEAD case, and it is deliberately not an
  # error: a caller with no readable branch has no basis on which to call the
  # marker somebody else's, and the same asymmetry applies — refusing to latch
  # there would silently disarm completion for the whole run. `${2:?}` would
  # instead abort the caller's shell, which is how a guard turns into an outage.
  [ -n "$branch" ] || return 0
  ! cbr_marker_is_foreign "$marker" "$branch"
}

# ---------------------------------------------------------------------------
# cbr_live_cwds — every process's current directory, one per line.
#
# A process's cwd is the outside-view proof that a folder is in use, and it
# needs no session registry to be true — which is exactly why it catches the
# sessions a registry does not know about. Prints nothing when the tool is
# unavailable; callers that must distinguish "nothing is live" from "cannot
# tell" check for the tool themselves.
# ---------------------------------------------------------------------------
cbr_live_cwds() {
  # Exit 2 means "could not look", which is NOT the same as "looked and found
  # nobody". Folding the two together is how a machine without the tool reports
  # every worktree as idle, and idle is the answer that authorises a reap.
  command -v lsof >/dev/null 2>&1 || return 2
  local out
  # The status has to be read from the TOOL, not from the filter downstream of
  # it: `lsof | sed` reports sed's success, and sed succeeds beautifully on no
  # input. A tool that exists and fails — a wrapper, a hardened host, a build
  # that rejects these flags — is the same epistemic state as one that is
  # missing, and it arrives here as an empty list and a clean exit, which reads
  # as "nobody is anywhere". Anything short of a complete answer is "could not
  # look": a PARTIAL table is not a safe compromise, because the one process it
  # omits may be the occupant the caller is asking about.
  out="$(lsof -w -d cwd -F n 2>/dev/null)" || return 2
  printf '%s\n' "$out" | sed -n 's/^n//p'
}

# ---------------------------------------------------------------------------
# cbr_path_has_live_process PATH [CWDS]
#   exit 0 = something is rooted there · 1 = nothing is · 2 = could not tell
#
# A shell sitting in `src/` is as much "in use" as one at the root, so a cwd
# anywhere UNDER the path counts. Compared as path prefixes rather than by
# regex: a real path may contain regex metacharacters.
#
# Pass CWDS (one cwd per line, from `cbr_live_cwds`) when asking about many
# paths — one sweep of the process table answers all of them.
# ---------------------------------------------------------------------------
cbr_path_has_live_process() {
  local path="${1:?path required}" cwds="${2-}" real cwd probe=0
  # A path that does not exist holds nobody. A path that EXISTS and cannot be
  # entered is a question this function was not able to ask — the same "could
  # not look" as a missing tool, and not the answer that authorises a reap.
  if ! real="$(cd "$path" 2>/dev/null && pwd -P)"; then
    # Something that exists and cannot be entered is a question this function
    # did not get to ask.
    if [ -e "$path" ] || [ -L "$path" ]; then return 2; fi
    # Absence is only provable from a readable parent: under an unreadable one,
    # `[ -e ]` fails for a path that is really there, and "I could not look in
    # there" must not report as "nobody is in there". A parent that does not
    # exist at all does prove the child's absence.
    local parent; parent="$(dirname "$path")"
    if [ -r "$parent" ] || [ ! -e "$parent" ]; then return 1; fi
    return 2
  fi
  if [ -z "${2+set}" ]; then
    cwds="$(cbr_live_cwds)" || probe=$?
    # 2 = the process table could not be inspected. Report that, rather than
    # letting a missing tool answer a question about who is working where.
    [ "$probe" -eq 0 ] || return 2
  fi
  [ -n "$cwds" ] || return 1
  while IFS= read -r cwd; do
    case "$cwd" in "$real"|"$real"/*) return 0 ;; esac
  done <<EOF
$cwds
EOF
  return 1
}

# ---------------------------------------------------------------------------
# cbr_branch_is_merged REPO BRANCH REF   (exit 0 = BRANCH's history is in REF)
# ---------------------------------------------------------------------------
cbr_branch_is_merged() {
  local repo="${1:?repo required}" branch="${2:?branch required}" ref="${3:?ref required}"
  git -C "$repo" merge-base --is-ancestor "$branch" "$ref" 2>/dev/null
}

# ---------------------------------------------------------------------------
# cbr_stage_paths REPO PATH...
#
# Stage what closeout produced so it rides the closeout commit instead of
# lingering as untracked debris nobody notices until the next `git status`.
#
# `add -A` on each path, with no existence precondition: a path closeout
# DELETED is work too, and skipping the absent ones would leave the removal
# unstaged — the closeout commit would then quietly keep the very marker the
# ritual just removed. A path git refuses (one outside the repository, say) is
# reported, not swallowed: unstaged closeout work is invisible until someone
# reads `git status`, which by then is a human noticing a mistake rather than a
# gate catching one.
#
# Prints `staged=<n>` and returns non-zero if any path could not be staged.
# ---------------------------------------------------------------------------
cbr_stage_paths() {
  local repo="${1:?repo required}"
  shift
  local n=0 p rc=0
  for p in "$@"; do
    [ -n "$p" ] || continue
    if git -C "$repo" add -A -- "$p" 2>/dev/null; then
      n=$((n + 1))
    else
      echo "strand-lib: could not stage $p in $repo" >&2
      rc=1
    fi
  done
  echo "staged=$n"
  return "$rc"
}

# ---------------------------------------------------------------------------
# cbr_closeout_base_duties REPO STRAND_BRANCH BASE_BRANCH ARCHIVE_DIR \
#                          MARKER PLAN [RECORD...]
#
# The three duties closeout owes the base branch, performed in the order that
# survives an interruption: SAVE first, then remove, then reground.
#
# This composite exists so a harness with more than one leaf has exactly ONE
# implementation of the ritual — the law in `build-loop.md` step 9 asks for
# that by name, and for the reason it gives: two copies of a rule this quiet
# drift invisibly, because the damage lands on the NEXT strand rather than
# this one. A leaf supplies its own record filenames and paths and calls this;
# it does not re-derive the steps.
#
# Everything the duties touch is STAGED, so the closeout commit carries the
# whole ritual as one deliberate act.
#
# Safe to re-run. Duty 1 failing stops the ritual with the base untouched, and
# duties 2 and 3 are individually idempotent, so a closeout interrupted anywhere
# can simply be run again — a ritual nobody dares repeat is a ritual that gets
# finished by hand.
#
# Prints one summary line; returns non-zero if any duty failed.
# ---------------------------------------------------------------------------
cbr_closeout_base_duties() {
  local repo="${1:?repo required}" strand="${2:?strand branch required}"
  local base="${3:?base branch required}" dest="${4:?archive dir required}"
  local marker="${5:?marker path required}" plan="${6:?plan path required}"
  shift 6

  local rc=0 archived marker_state reground_state staged

  # Before duty 1: an archive already sitting at the destination is a retry only
  # if it can be shown to belong to this strand. This lives HERE rather than in a
  # leaf's closeout because every leaf reaches the duties through this function —
  # a guard implemented at one call site is a guard the other leaf does not have.
  if ! cbr_archive_dest_is_contained "$repo" "$dest"; then
    echo "closeout-duties archive-path-unsafe marker=skipped reground=skipped staged=0"
    echo "strand-lib: archive destination is not a real path inside $repo: $dest" >&2
    return 1
  fi
  if [ -e "$dest" ] || [ -L "$dest" ]; then
    if [ -L "$dest" ] || [ ! -d "$dest" ]; then
      echo "closeout-duties archive-path-not-a-directory marker=skipped reground=skipped staged=0"
      echo "strand-lib: archive path is a symlink or not a directory: $dest" >&2
      return 1
    fi
    if ! cbr_archive_is_retry_of "$dest" "$repo" "$strand"; then
      echo "closeout-duties archive-belongs-elsewhere marker=skipped reground=skipped staged=0"
      echo "strand-lib: $dest is not an interrupted attempt at archiving $strand ($(git -C "$repo" rev-parse -q --verify "$strand^{commit}" 2>/dev/null)) — it belongs to another run; move it aside by hand" >&2
      return 1
    fi
  fi

  # Duty 1 — archive out of the strand's final commit, BEFORE anything is
  # removed, and STOP THERE if it fails. Returning early is the whole safety
  # property: the base is still untouched, so the caller can fix the cause and
  # re-run, where continuing would remove the marker and reground the plan on
  # behalf of an archive that does not exist.
  #
  # The fork point scopes the archive to what the strand authored; when it
  # cannot be established the archiver runs unfiltered, because losing a real
  # record is worse than keeping an inherited one.
  local fork
  fork="$(cbr_strand_fork_point "$repo" "$strand" "$base")" || fork=""
  if ! archived="$(CBR_ARCHIVE_FORK="$fork" cbr_archive_strand_records "$repo" "$strand" "$dest" "$@")"; then
    echo "closeout-duties $archived marker=skipped reground=skipped staged=0"
    return 1
  fi

  # Duty 2 — the completion marker does not survive on the base.
  marker_state="$(cbr_remove_marker_from_base "$repo" "$marker")" || rc=1

  # Duty 3 — the base plan names the base again.
  reground_state="$(cbr_reground_plan_branch "$repo/$plan" "$base")" || rc=1

  # Stage the archive and the plan; the marker removal is already staged by
  # duty 2 when the marker was tracked.
  local rel="$dest"
  case "$dest" in "$repo"/*) rel="${dest#"$repo"/}" ;; esac
  staged="$(cbr_stage_paths "$repo" "$rel" "$plan")" || rc=1

  echo "closeout-duties $archived $marker_state $reground_state $staged"
  return "$rc"
}

# cbr_tool_staleness_report [PINNED_PROBITY_VERSION]
#
# WARN-only staleness probe for the harness's own tooling (backlog 2026-08-27:
# the review tool sat 6 versions behind with nobody noticing). Prints one line
# per stale tool and NOTHING else; every failure path — tool missing, network
# down, output unparseable, no pin known — is silent and exits 0. This probe
# may only SURFACE: updating a tool or bumping a pin is a human decision, and
# a doctor must never fail over its own infra (fail-open law).
# cbr_version_lt A B — true iff dotted-numeric version A is strictly lower
# than B. Every component compares numerically (10.2 > 9.9), omitted
# components are zero (1.2 == 1.2.0), any depth (1.2.3.4.1 < 1.2.3.4.2).
# Non-numeric text in a component coerces to 0 rather than erroring, which
# the fail-open caller tolerates.
cbr_version_lt() {
  awk -v a="$1" -v b="$2" 'BEGIN{
    na=split(a,A,"."); nb=split(b,B,".");
    n=(na>nb)?na:nb;
    for(i=1;i<=n;i++){ x=(i<=na)?A[i]+0:0; y=(i<=nb)?B[i]+0:0;
      if(x<y) exit 0; if(x>y) exit 1 }
    exit 1 }'
}

cbr_tool_staleness_report() {
  local pin="${1:-}" out cur latest
  if command -v roborev >/dev/null 2>&1; then
    # `update` without --yes prints current/latest and installs nothing when
    # stdin is not a TTY; </dev/null makes that unconditional.
    out="$(roborev update </dev/null 2>/dev/null || true)"
    cur="$(printf '%s\n' "$out" | sed -nE 's/.*Current version:[[:space:]]*v?([0-9][0-9.]*).*/\1/p' | head -1)"
    latest="$(printf '%s\n' "$out" | sed -nE 's/.*Latest version:[[:space:]]*v?([0-9][0-9.]*).*/\1/p' | head -1)"
    # Behind is DIRECTIONAL: a locally newer build (dev build) is not stale.
    if [ -n "$cur" ] && [ -n "$latest" ] && cbr_version_lt "$cur" "$latest"; then
      echo "tool-staleness: roborev v$cur -> v$latest available (human decision: roborev update)"
    fi
  fi
  if [ -n "$pin" ] && command -v npm >/dev/null 2>&1; then
    latest="$(npm view @nizos/probity version 2>/dev/null | head -1 || true)"
    if [ -n "$latest" ] && cbr_version_lt "$pin" "$latest"; then
      echo "tool-staleness: probity pinned $pin, latest $latest (human decision: bump the pin deliberately)"
    fi
  fi
  return 0
}

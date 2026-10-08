#!/usr/bin/env bash
# Comprehensive tests for ./kai — every command + error path.
set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SRC_KAI="${REPO}/kai"

PASS=0
FAIL=0
failures=()
LAST_OUT=""
ROOT=""

red() { printf '\033[31m%s\033[0m\n' "$*"; }
green() { printf '\033[32m%s\033[0m\n' "$*"; }

ok() {
  PASS=$((PASS + 1))
}

bad() {
  local name="$1"
  FAIL=$((FAIL + 1))
  failures+=("$name")
  red "FAIL $name"
}

assert_eq() {
  local name="$1" got="$2" want="$3"
  if [[ "$got" == "$want" ]]; then
    ok
  else
    bad "$name: got=$(printf '%q' "$got") want=$(printf '%q' "$want")"
  fi
}

assert_contains() {
  local name="$1" hay="$2" needle="$3"
  if [[ "$hay" == *"$needle"* ]]; then
    ok
  else
    bad "$name: missing $(printf '%q' "$needle") in $(printf '%q' "$hay")"
  fi
}

assert_not_contains() {
  local name="$1" hay="$2" needle="$3"
  if [[ "$hay" != *"$needle"* ]]; then
    ok
  else
    bad "$name: unexpected $(printf '%q' "$needle")"
  fi
}

# Run command; expect success. Sets LAST_OUT.
run_ok() {
  local name="$1"
  shift
  local rc=0
  LAST_OUT="$("$@" 2>&1)" || rc=$?
  if (( rc == 0 )); then
    ok
  else
    bad "$name: expected ok rc=$rc out=$(printf '%q' "$LAST_OUT")"
    LAST_OUT=""
  fi
}

# Run command; expect failure. Sets LAST_OUT.
run_fail() {
  local name="$1"
  shift
  local rc=0
  LAST_OUT="$("$@" 2>&1)" || rc=$?
  if (( rc != 0 )); then
    ok
  else
    bad "$name: expected fail, got ok out=$(printf '%q' "$LAST_OUT")"
  fi
}

new_board() {
  local root
  root="$(mktemp -d "${TMPDIR:-/tmp}/kai-test.XXXXXX")"
  # Consumer layout: CLI at repo root, board data under .kai/
  cp "$SRC_KAI" "${root}/kai"
  chmod +x "${root}/kai"
  echo "$root"
}

write_config() {
  local root="$1"
  cat > "${root}/.kai/config"
}

K() {
  (cd "$ROOT" && ./kai "$@")
}

cleanup() {
  [[ -n "${ROOT:-}" && -d "${ROOT:-}" ]] && rm -rf "$ROOT"
  ROOT=""
}

# ---------- suites ----------

test_init() {
  ROOT="$(new_board)"
  run_ok init_fresh K init TestPref
  assert_contains init_msg "$LAST_OUT" "initialized"
  assert_contains init_prefix "$(cat "${ROOT}/.kai/config")" "prefix=TestPref"
  assert_contains init_workflow "$(cat "${ROOT}/.kai/config")" "workflow="
  run_ok init_again K init Other
  assert_contains init_idempotent "$LAST_OUT" "already initialized"
  cleanup
}

test_help_and_unknown() {
  ROOT="$(new_board)"
  K init >/dev/null
  run_ok help K help
  assert_contains help_text "$LAST_OUT" "Usage:"
  run_ok help_h K -h
  assert_contains help_h_wf "$LAST_OUT" "workflow"
  run_fail unk K nosuch
  assert_contains fail_unknown "$LAST_OUT" "unknown command"
  cleanup
}

test_cli_root() {
  ROOT="$(new_board)"
  K init >/dev/null
  run_ok cli_list K list
  assert_contains cli_list_h "$LAST_OUT" "## todo"
  # Board data is under .kai/, CLI is not.
  [[ -f "${ROOT}/.kai/config" ]] && ok || bad "cli_board_data"
  [[ ! -e "${ROOT}/.kai/kai" ]] && ok || bad "cli_not_under_dot"
  cleanup
}

test_add_list_show_board() {
  ROOT="$(new_board)"
  K init >/dev/null
  run_ok add_u K add --author user --title "U task" --priority 10 --body "hello"
  assert_contains add_u_id "$LAST_OUT" "KaiU001"
  run_ok add_a K add --author ai --title "A task" --priority 20 --column todo
  assert_contains add_a_id "$LAST_OUT" "KaiA001"
  run_ok list K list
  assert_contains list_a "$LAST_OUT" "KaiA001"
  assert_contains list_ready "$LAST_OUT" "[ready]"
  run_ok show K show KaiU001
  assert_contains show_body "$LAST_OUT" "hello"
  assert_contains show_status "$LAST_OUT" "status:"
  run_ok board K board
  assert_contains board_out "$LAST_OUT" "Kanban Board"
  assert_contains board_file "$(cat "${ROOT}/.kai/BOARD.md")" "KaiA001"
  cleanup
}

test_list_options() {
  ROOT="$(new_board)"
  K init >/dev/null
  local i
  for i in 1 2 3 4 5 6; do
    K add --author ai --title "t$i" --priority "$i" >/dev/null
  done
  run_ok list_lim K list --column todo
  assert_contains list_more "$LAST_OUT" "more (use --all)"
  run_ok list_all K list --all --column todo
  assert_contains list_all6 "$LAST_OUT" "KaiA006"
  run_ok list_det K list --details --column todo
  run_fail lob K list --nope
  assert_contains list_bad_opt "$LAST_OUT" "unknown list option"
  run_fail lbc K list --column nope
  assert_contains list_bad_col "$LAST_OUT" "unknown column"
  run_fail lcn K list --column
  assert_contains list_col_needs "$LAST_OUT" "--column needs"
  cleanup
}

test_workflow_enforcement() {
  ROOT="$(new_board)"
  K init >/dev/null
  K add --author ai --title "w" --priority 1 >/dev/null
  run_ok wf_show K workflow
  assert_contains wf_line "$LAST_OUT" "todo → doing"
  run_fail td K move KaiA001 done
  assert_contains skip_done "$LAST_OUT" "workflow: cannot todo → done"
  run_ok mv_doing K move KaiA001 doing
  run_ok mv_done K done KaiA001
  run_ok in_done K list --column done --all
  assert_contains in_done_id "$LAST_OUT" "KaiA001"
  run_ok reopen K move KaiA001 todo
  cleanup
}

test_depends_soft_hard_ready() {
  ROOT="$(new_board)"
  K init >/dev/null
  K add --author user --title "base" --priority 10 >/dev/null
  K add --author ai --title "parallel" --priority 5 >/dev/null
  K add --author ai --title "blocked" --priority 20 --depends KaiU001 >/dev/null

  run_ok ready K ready
  assert_contains ready_base "$LAST_OUT" "KaiU001"
  assert_contains ready_par "$LAST_OUT" "KaiA001"
  assert_not_contains ready_hide "$LAST_OUT" "KaiA002"

  run_ok list K list
  assert_contains blocked_mark "$LAST_OUT" "[blocked: KaiU001]"

  run_ok soft_move K move KaiA002 doing
  run_ok soft_back K move KaiA002 todo

  sed -i 's/deps_mode=soft/deps_mode=hard/' "${ROOT}/.kai/config"
  run_fail hm K move KaiA002 doing
  assert_contains hard_rej "$LAST_OUT" "blocked (hard)"

  # Reach doing under soft, then hard rejects done (workflow allows doing→done).
  sed -i 's/deps_mode=hard/deps_mode=soft/' "${ROOT}/.kai/config"
  K move KaiA002 doing >/dev/null
  sed -i 's/deps_mode=soft/deps_mode=hard/' "${ROOT}/.kai/config"
  run_fail hd K done KaiA002
  assert_contains hard_done "$LAST_OUT" "blocked (hard)"
  run_ok hard_demote K move KaiA002 todo

  sed -i 's/deps_mode=hard/deps_mode=soft/' "${ROOT}/.kai/config"
  K move KaiU001 doing >/dev/null
  K done KaiU001 >/dev/null
  run_ok ready_after K ready
  assert_contains ready_unblocked "$LAST_OUT" "KaiA002"

  run_fail rb K ready --nope
  assert_contains ready_bad "$LAST_OUT" "unknown ready option"
  run_ok ready_det K ready --details --all
  assert_contains ready_det_id "$LAST_OUT" "KaiA002"
  cleanup
}

test_depend_undepend_cycle() {
  ROOT="$(new_board)"
  K init >/dev/null
  K add --author ai --title "a" >/dev/null
  K add --author ai --title "b" >/dev/null
  run_ok dep K depend KaiA002 KaiA001
  run_ok has_dep K show KaiA002
  assert_contains has_dep_line "$LAST_OUT" "depends: KaiA001"
  run_fail cy K depend KaiA001 KaiA002
  assert_contains cycle "$LAST_OUT" "dependency cycle"
  run_fail sc K depend KaiA001 KaiA001
  assert_contains self_cycle "$LAST_OUT" "dependency cycle"
  run_fail md K depend KaiA001 KaiZ999
  assert_contains miss_dep "$LAST_OUT" "missing item"
  run_ok undep K undepend KaiA002 KaiA001
  run_ok show_after K show KaiA002
  assert_not_contains no_dep_line "$LAST_OUT" "depends:"
  run_fail um K undepend KaiA002 KaiA001
  assert_contains undep_miss "$LAST_OUT" "does not depend"
  run_fail amd K add --author ai --title x --depends KaiZ9
  assert_contains add_miss_dep "$LAST_OUT" "missing item"
  cleanup
}

test_priority_image_errors() {
  ROOT="$(new_board)"
  K init >/dev/null
  K add --author user --title "p" >/dev/null
  run_ok pri K priority KaiU001 99
  run_ok pri_show K show KaiU001
  assert_contains pri_val "$LAST_OUT" "priority: 99"
  run_fail pb K priority KaiU001 no
  assert_contains pri_bad "$LAST_OUT" "integer"
  run_fail pu K priority
  assert_contains pri_usage "$LAST_OUT" "usage:"

  printf 'x' > "${ROOT}/dot.bin"
  run_ok img K image "${ROOT}/dot.bin"
  assert_contains img_path "$LAST_OUT" ".kai/images/img-001.bin"
  run_ok img2 K image "${ROOT}/dot.bin"
  assert_contains img2_path "$LAST_OUT" "img-002"
  run_fail im K image /no/such
  assert_contains img_miss "$LAST_OUT" "file not found"
  run_fail iu K image
  assert_contains img_usage "$LAST_OUT" "usage:"

  run_fail sm K show Nope
  assert_contains show_miss "$LAST_OUT" "not found"
  run_fail su K show
  assert_contains show_usage "$LAST_OUT" "usage:"
  run_fail mu K move
  assert_contains move_usage "$LAST_OUT" "usage:"
  run_fail mc K move KaiU001 ghost
  assert_contains move_badcol "$LAST_OUT" "unknown column"
  run_fail du K done
  assert_contains done_usage "$LAST_OUT" "usage:"
  run_fail dpu K depend
  assert_contains depend_usage "$LAST_OUT" "usage:"
  run_fail udu K undepend
  assert_contains undepend_usage "$LAST_OUT" "usage:"
  cleanup
}

test_add_validation() {
  ROOT="$(new_board)"
  K init >/dev/null
  run_fail ana K add --title x
  assert_contains add_no_author "$LAST_OUT" "requires --author"
  run_fail ant K add --author ai
  assert_contains add_no_title "$LAST_OUT" "requires --title"
  run_fail aba K add --author dog --title x
  assert_contains add_bad_author "$LAST_OUT" "user or ai"
  run_fail abc K add --author ai --title x --column ghost
  assert_contains add_bad_col "$LAST_OUT" "unknown column"
  run_fail abp K add --author ai --title x --priority zz
  assert_contains add_bad_pri "$LAST_OUT" "integer"
  run_fail au K add --author ai --title x --foo
  assert_contains add_unk "$LAST_OUT" "unknown add option"
  run_fail aan K add --author
  assert_contains add_author_needs "$LAST_OUT" "--author needs"
  run_fail atn K add --author ai --title
  assert_contains add_title_needs "$LAST_OUT" "--title needs"
  run_fail acn K add --author ai --title x --column
  assert_contains add_col_needs "$LAST_OUT" "--column needs"
  run_fail apn K add --author ai --title x --priority
  assert_contains add_pri_needs "$LAST_OUT" "--priority needs"
  run_fail abn K add --author ai --title x --body
  assert_contains add_body_needs "$LAST_OUT" "--body needs"
  run_fail adn K add --author ai --title x --depends
  assert_contains add_dep_needs "$LAST_OUT" "--depends needs"
  cleanup
}

test_config_errors() {
  ROOT="$(new_board)"
  run_fail nc K list
  assert_contains no_cfg "$LAST_OUT" "missing"

  K init >/dev/null

  write_config "$ROOT" <<'EOF'
columns=todo,doing,done
deps_mode=soft
EOF
  run_fail np K list
  assert_contains no_prefix "$LAST_OUT" "prefix is required"

  write_config "$ROOT" <<'EOF'
prefix=Kai
deps_mode=soft
EOF
  run_fail nco K list
  assert_contains no_cols "$LAST_OUT" "columns is required"

  write_config "$ROOT" <<'EOF'
prefix=Kai
columns=todo,doing,done
deps_mode=weird
EOF
  run_fail bm K list
  assert_contains bad_mode "$LAST_OUT" "deps_mode must be"

  write_config "$ROOT" <<'EOF'
prefix=Kai
columns=todo,doing,done
workflow=todo-doing
deps_mode=soft
EOF
  run_fail bw K list
  assert_contains bad_wf "$LAST_OUT" "missing '>'"

  write_config "$ROOT" <<'EOF'
prefix=Kai
columns=todo,doing,done
workflow=ghost>doing
deps_mode=soft
EOF
  run_fail bf K list
  assert_contains bad_from "$LAST_OUT" "from-column unknown"

  write_config "$ROOT" <<'EOF'
prefix=Kai
columns=todo,doing,done
workflow=todo>ghost
deps_mode=soft
EOF
  run_fail bt K list
  assert_contains bad_to "$LAST_OUT" "to-column unknown"

  write_config "$ROOT" <<'EOF'
prefix=Kai
columns=todo,doing,done
start_column=ghost
deps_mode=soft
EOF
  run_fail bs K list
  assert_contains bad_start "$LAST_OUT" "start_column not in columns"

  write_config "$ROOT" <<'EOF'
prefix=Kai
columns=todo,doing,done
done_column=ghost
deps_mode=soft
EOF
  run_fail bd K list
  assert_contains bad_done "$LAST_OUT" "done_column not in columns"

  write_config "$ROOT" <<'EOF'
prefix=Kai
columns=todo,doing,done
deps_mode=soft
EOF
  run_ok def_wf K workflow
  assert_contains def_wf_line "$LAST_OUT" "todo → doing"

  write_config "$ROOT" <<'EOF'
prefix=X
columns=backlog,wip,ship
deps_mode=soft
EOF
  run_ok lin_wf K workflow
  assert_contains lin_wf1 "$LAST_OUT" "backlog → wip"
  assert_contains lin_wf2 "$LAST_OUT" "wip → ship"

  write_config "$ROOT" <<'EOF'
prefix=Kai
columns=todo,doing,done
workflow=todo>doing|doing>done|done>
deps_mode=soft
EOF
  mkdir -p "${ROOT}/.kai/items" "${ROOT}/.kai/images"
  touch "${ROOT}/.kai/items/.gitkeep"
  K add --author ai --title z >/dev/null
  K move KaiA001 doing >/dev/null
  K move KaiA001 done >/dev/null
  run_fail term K move KaiA001 todo
  assert_contains term_msg "$LAST_OUT" "allowed: (none)"
  run_ok wf_none K workflow
  assert_contains wf_none_line "$LAST_OUT" "done → (none)"

  write_config "$ROOT" <<'EOF'
# comment
prefix=Kai

columns=todo,doing,done
workflow=todo>doing|doing>todo,done|done>todo
deps_mode=soft
EOF
  run_ok cfg_comments K list
  cleanup
}

test_list_empty_and_same_column_move() {
  ROOT="$(new_board)"
  K init >/dev/null
  run_ok empty K list
  assert_contains empty_msg "$LAST_OUT" "(empty)"
  run_ok ready_none K ready
  assert_contains ready_none_msg "$LAST_OUT" "(none)"
  K add --author ai --title "s" >/dev/null
  run_ok same K move KaiA001 todo
  run_ok brd K board
  assert_contains brd_empty "$LAST_OUT" "_empty_"
  cleanup
}

test_image_no_ext_and_join_depends() {
  ROOT="$(new_board)"
  K init >/dev/null
  K add --author user --title "d1" >/dev/null
  K add --author user --title "d2" >/dev/null
  printf 'y' > "${ROOT}/noext"
  run_ok noext K image "${ROOT}/noext"
  assert_contains noext_path "$LAST_OUT" "img-001.png"
  run_ok multi K add --author ai --title "multi" --depends "KaiU001, KaiU002"
  run_ok multi_show K show KaiA001
  assert_contains multi_dep "$LAST_OUT" "depends: KaiU001,KaiU002"
  run_ok dup K depend KaiA001 KaiU001
  cleanup
}

test_fm_set_insert_missing_key() {
  ROOT="$(new_board)"
  K init >/dev/null
  K add --author ai --title "x" >/dev/null
  local f="${ROOT}/.kai/items/KaiA001.md"
  awk 'BEGIN{n=0} /^---/{n++; print; next} n==1 && /^priority:/{next} {print}' "$f" > "${f}.t"
  mv "${f}.t" "$f"
  run_ok reins K priority KaiA001 7
  run_ok reins_show K show KaiA001
  assert_contains reins_v "$LAST_OUT" "priority: 7"
  cleanup
}

test_ready_more_and_board_blocked() {
  ROOT="$(new_board)"
  K init >/dev/null
  # 6 ready items to hit ready --all truncate path
  local i
  for i in 1 2 3 4 5 6; do
    K add --author ai --title "r$i" --priority "$i" >/dev/null
  done
  run_ok ready_lim K ready
  assert_contains ready_more "$LAST_OUT" "more (use --all)"
  K add --author user --title "blk" --depends KaiA001 >/dev/null
  # leave KaiA001 open so U001 blocked
  run_ok board_blk K board
  assert_contains board_blk_mark "$LAST_OUT" "[blocked:"
  cleanup
}

test_help_long() {
  ROOT="$(new_board)"
  K init >/dev/null
  run_ok hl K --help
  assert_contains hl_deps "$LAST_OUT" "deps_mode"
  cleanup
}

# ---------- run ----------

echo "kai tests (repo=${REPO})"
test_init
test_help_and_unknown
test_cli_root
test_add_list_show_board
test_list_options
test_workflow_enforcement
test_depends_soft_hard_ready
test_depend_undepend_cycle
test_priority_image_errors
test_add_validation
test_config_errors
test_list_empty_and_same_column_move
test_image_no_ext_and_join_depends
test_fm_set_insert_missing_key
test_ready_more_and_board_blocked
test_help_long

echo ""
echo "passed=$PASS failed=$FAIL"
if (( FAIL > 0 )); then
  red "Failures:"
  for f in "${failures[@]}"; do
    red "  - $f"
  done
  exit 1
fi
green "ALL OK"

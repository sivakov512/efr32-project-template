#!/bin/sh
# Copy the reusable part of this template into an existing SLC project, for
# example one started from a Simplicity Studio example. Run from anywhere:
#
#   ~/path/to/efr32-project-template/apply.sh /path/to/project
#   ~/path/to/efr32-project-template/apply.sh --remove /path/to/project
#
# Project files that differ from the template are reported and kept, both when
# applying and when removing; --diff shows the differences, --force acts anyway.
set -eu

# Copied into the project.
FILES='
Makefile
tools/compile_db.py
tools/slcp_info.py
.clang-format
.clang-tidy
.clangd
.gitignore
.zed/settings.json
.zed/tasks.json
.github/workflows/formatting.yml
'
# Never copied: the template's own docs, starter sources and this script.
TEMPLATE_ONLY='
README.md
apply.sh
app.c
app.h
main.c
tbd.slcp
'

usage() {
    cat >&2 <<'USAGE'
usage: apply.sh [--dry-run] [--diff] [--force] [--remove] PROJECT_DIR
  -n, --dry-run  report only, write nothing
  --diff         show how existing project files differ from the template
  --force        overwrite, or with --remove delete, project files that differ
  --remove       delete the template files from the project instead of copying
USAGE
    exit 2
}

die() {
    echo "ERROR: $*" >&2
    exit 1
}

# Delete a project file and the directories that leaves empty (tools, .zed, ...).
remove_file() {
    rm "$target/$1"
    (cd "$target" && rmdir -p "$(dirname "$1")" 2>/dev/null) || true
}

dry_run= show_diff= force= remove= target=
while [ $# -gt 0 ]; do
    case $1 in
        -n|--dry-run) dry_run=1 ;;
        --diff) show_diff=1 ;;
        --force) force=1 ;;
        --remove) remove=1 ;;
        -*) usage ;;
        *) [ -z "$target" ] || usage; target=$1 ;;
    esac
    shift
done
[ -n "$target" ] || usage

template=$(cd "$(dirname "$0")" && pwd -P)
[ -d "$target" ] || die "$target is not a directory"
target=$(cd "$target" && pwd -P)
[ "$target" != "$template" ] || die "the target is the template itself"
set -- "$target"/*.slcp
[ $# -eq 1 ] && [ -f "$1" ] || die "$target must contain exactly one .slcp; is it an SLC project?"

# A file added to the template must be put in one of the lists above.
for f in $(git -C "$template" ls-files 2>/dev/null); do
    printf '%s\n' $FILES $TEMPLATE_ONLY | grep -qxF "$f" \
        || echo "WARNING: $f is not in FILES or TEMPLATE_ONLY in apply.sh" >&2
done

if [ -n "$remove" ]; then
    echo "Removing $(basename "$template") files from $target"
else
    echo "Applying $(basename "$template") to $target"
fi
[ -z "$dry_run" ] || echo "Dry run: nothing is written"
differs=0
for f in $FILES; do
    src=$template/$f
    dst=$target/$f
    # Decide for apply mode; --remove reinterprets the same three cases.
    if [ ! -e "$dst" ]; then
        action=copy;      [ -z "$remove" ] || action=absent
    elif cmp -s "$src" "$dst"; then
        action=unchanged; [ -z "$remove" ] || action=remove
    elif [ -n "$force" ]; then
        action=overwrite; [ -z "$remove" ] || action=remove
    else
        action=differs
        differs=$((differs + 1))
    fi
    printf '%-10s %s\n' "$action" "$f"
    if [ -n "$show_diff" ]; then
        case $action in differs|overwrite|remove) diff -u "$dst" "$src" || true ;; esac
    fi
    if [ -z "$dry_run" ]; then
        case $action in
            copy|overwrite) mkdir -p "$(dirname "$dst")"; cp "$src" "$dst" ;;
            remove) remove_file "$f" ;;
        esac
    fi
done
if [ "$differs" -gt 0 ]; then
    verb=overwrite; [ -z "$remove" ] || verb=remove
    echo "$differs file(s) differ from the template: rerun with --diff to see the changes or --force to $verb"
fi

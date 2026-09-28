#!/usr/bin/env bash
# Syntax check every lua file, run the static checks, then run the specs under
# LuaJIT.
#
# LuaJIT cannot catch API misuse -- PZ globals do not exist outside the game,
# and it will happily accept next(), which PZ's sandbox does not expose, and
# loadstring, which B42.20.4 removed. What it can do is parse every file and
# run the parts of this mod that are pure Lua, which is the point registry and
# the whole of the unlock bookkeeping.
#
# The static checks below are not stylistic. Each is a bug class that LuaJIT
# cannot see and that PhunInteriors has already been bitten by; they are
# cheaper to carry from the start than to add after the first one lands.
set -u
cd "$(dirname "$0")/.."
ROOT="$(pwd)"
LJ="${LUAJIT:-$HOME/AppData/Local/Programs/LuaJIT/bin/luajit}"

if [ ! -x "$LJ" ] && ! command -v "$LJ" >/dev/null 2>&1; then
    echo "luajit not found; set LUAJIT=/path/to/luajit" >&2
    exit 2
fi

status=0

for f in $(find Contents/mods/PhunTaxi -name "*.lua"); do
    if ! "$LJ" -bl "$f" >/dev/null 2>&1; then
        echo "SYNTAX $f"
        "$LJ" -bl "$f" 2>&1 | head -3
        status=1
    fi
done
[ $status -eq 0 ] && echo "syntax           all files parse"

# Nothing may be hung off the Core table under a name core.lua already
# declares. A function named for one of those fields REPLACES it, silently, at
# file load time. PhunInteriors defined a Core.rooms() console helper in a
# client file and it took out the registry table for every client and every
# single player session, so the first registration indexed a function and the
# mod did not boot. The specs cannot see it: they load the shared and server
# halves, and that collision was in a client file.
clashes=$(perl -e '
    my ($core, @files) = @ARGV;
    open(my $c, "<", $core) or die "no core.lua";
    my (%field, $on);
    while (<$c>) {
        $on = 1, next if /^PhunTaxi = \{/;
        next unless $on;
        last if /^\}/;
        $field{$1} = 1 if /^    ([A-Za-z_][A-Za-z0-9_]*)\s*=/;
    }
    die "core.lua declared no fields -- has the table moved?" unless %field;
    for my $f (@files) {
        next if $f =~ m{shared/PhunTaxi/core\.lua$};
        open(my $h, "<", $f) or next;
        while (my $l = <$h>) {
            next unless $l =~ /^(?:function\s+)?(?:Core|PhunTaxi)\.([A-Za-z0-9_]+)\s*(\(|=\s*function)/;
            print "$f:$.: $1\n" if $field{$1};
        }
    }
' Contents/mods/PhunTaxi/common/media/lua/shared/PhunTaxi/core.lua \
  $(find Contents/mods/PhunTaxi -name "*.lua")) || status=1
if [ -n "$clashes" ]; then
    echo "NAMESPACE a function is replacing a Core field declared in core.lua:"
    echo "$clashes"
    status=1
elif [ $status -eq 0 ]; then
    echo "namespace        no Core field is shadowed by a function"
fi

# The unlock cache is written in exactly one place. It is a copy of what the
# character record says, and a second write site is how the copy and the truth
# come to disagree -- which reads as a player losing an unlock they can see
# they have.
writes=$(grep -rn "Core\.unlocked\[[^]]*\] *=" --include="*.lua" \
             Contents/mods/PhunTaxi \
         | grep -v "server/PhunTaxi/unlocks\.lua:")
if [ -n "$writes" ]; then
    echo "UNLOCKS something outside unlocks.lua writes the unlock cache:"
    echo "$writes"
    status=1
else
    echo "unlocks          only unlocks.lua writes the unlock cache"
fi

# A local redeclared at the top level of the same function. LuaJIT parses one
# happily and the damage shows up somewhere else entirely -- see shadow.pl.
shadows=$(perl scripts/shadow.pl $(find Contents/mods/PhunTaxi -name "*.lua"))
if [ -n "$shadows" ]; then
    echo "SHADOW a local is being redeclared inside one function:"
    echo "$shadows"
    status=1
else
    echo "shadows          no local shadows another in the same function"
fi

# No em dashes. Anywhere: not in code comments, not in translations, not in
# anything a player reads. Where one would go, use -- or recast the sentence.
# Octal escapes rather than a \u escape: older bash passes \u through
# unexpanded, so the pattern becomes a literal string that this very file
# contains, and the check reports itself.
EMDASH=$(printf '\342\200\224')
dashes=$(grep -rln "$EMDASH" Contents Tests Docs scripts README.md CLAUDE.md workshop.txt 2>/dev/null)
if [ -n "$dashes" ]; then
    echo "DASHES em dashes found in:"
    echo "$dashes"
    status=1
else
    echo "dashes           no em dashes"
fi

# No globals but PhunTaxi. A `function name()` or `name = ...` at the top of a
# file with no `local` is a global, and in a game where every mod shares one
# Lua state, a global is somebody else's bug waiting for the same name. Top
# level only; the map folder's objects.lua is the game's format, not ours.
globals=$(grep -rnE "^(function [A-Za-z_][A-Za-z0-9_]*\(|[A-Za-z_][A-Za-z0-9_]* *=[^=])" \
              --include="*.lua" Contents/mods/PhunTaxi \
          | grep -v "/media/maps/" | grep -v ":PhunTaxi = {")
if [ -n "$globals" ]; then
    echo "GLOBALS something other than PhunTaxi is declared global:"
    echo "$globals"
    status=1
else
    echo "globals          nothing global but PhunTaxi"
fi

# Every translation file is JSON. B42 reads them as JSON, and one stray comma
# loses the whole file: every key in it shows as its raw name.
badjson=""
for f in Contents/mods/PhunTaxi/common/media/lua/shared/Translate/*/*.json; do
    err=$("$LJ" -e "
        package.path = '${PHUNINTERIORS:-../PhunInteriors}/Contents/mods/PhunInteriors/common/media/lua/shared/?.lua;' .. package.path
        local json = require('PhunInteriors/json')
        local fh = assert(io.open('$f'))
        local _, err = json.decode(fh:read('*a'))
        if err then print(err) end" 2>&1)
    [ -n "$err" ] && badjson="$badjson$f: $err"$'\n'
done
if [ -n "$badjson" ]; then
    echo "JSON a translation file does not parse:"
    printf "%s" "$badjson"
    status=1
else
    echo "json             every translation file parses"
fi

for spec in Tests/lua/*_spec.lua; do
    PS_ROOT="$ROOT" "$LJ" "$spec" || status=1
done

exit $status

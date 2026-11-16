#!/bin/bash
# Tests for the bash completion in completions/check_tftp.
# Run: tests/test_completion.sh

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CHECK="$ROOT/check_tftp"
COMPLETION="$ROOT/completions/check_tftp"
HOSTS=$(mktemp)
trap 'rm -f "$HOSTS"' EXIT
# host names come from HOSTFILE
printf '%s\n' '192.0.2.1 pxe.example.com' '192.0.2.2 backup.example.com' > "$HOSTS"

FAILURES=0
TESTS=0

# the candidates, one per line, bash offers for the last argument, which may be empty
complete_words(){
	HOSTFILE="$HOSTS" bash -c 'source "$1"; shift; COMP_WORDS=(check_tftp "$@"); COMP_CWORD=$#
		_check_tftp; printf "%s\n" "${COMPREPLY[@]}"' bash "$COMPLETION" "$@" | grep . | sort
}

# expect NAME EXPECTED ACTUAL
expect(){
	TESTS=$((TESTS + 1))
	if [ "$2" == "$3" ]; then
		printf 'ok   %s\n' "$1"
	else
		FAILURES=$((FAILURES + 1))
		printf 'FAIL %s: expected\n%s\n     got\n%s\n' "$1" "$2" "$3"
	fi
}

TESTS=$((TESTS + 1))
if bash -n "$COMPLETION"; then echo "ok   syntax"; else FAILURES=$((FAILURES + 1)); echo "FAIL syntax"; fi

# the options -h lists
HELP_OPTIONS=$("$CHECK" -h | sed -n 's/^\(-[[:alnum:]]\) .*/\1/p' | sort)
expect "-h lists options" 11 "$(wc -l <<< "$HELP_OPTIONS")"
expect "exactly the options of -h" "$HELP_OPTIONS" "$(complete_words "")"
expect "option prefix" "-H" "$(complete_words -H)"
expect "host names" "pxe.example.com" "$(complete_words -H pxe)"
expect "no candidates for a port" "" "$(complete_words -p "")"
expect "options after a value" "-t" "$(complete_words -H pxe.example.com -t)"

echo "$((TESTS - FAILURES)) of $TESTS tests passed"
[ $FAILURES -eq 0 ]

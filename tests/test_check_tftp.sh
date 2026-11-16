#!/bin/bash
# Tests for check_tftp with a fake tftp command.
# Run: tests/test_check_tftp.sh

CHECK="$(cd "$(dirname "$0")/.." && pwd)/check_tftp"
FAKE_BIN=$(mktemp -d)
trap 'rm -rf "$FAKE_BIN"' EXIT

# tftp, controlled by FAKE_* variables; answers like tftp-hpa
cat > "$FAKE_BIN/tftp" <<'FAKE'
#!/bin/bash
printf '%s\n' "$@" > "${FAKE_LOG:-/dev/null}"
local=${@: -1}
[ -z "$FAKE_SLEEP" ] || sleep "$FAKE_SLEEP"
case "${FAKE_MODE:-ok}" in
	ok)
		# like a netascii transfer of a binary file, which gets CR added before LF
		if [[ " $* " == *" -m octet "* ]]; then
			head -c "${FAKE_SIZE:-1000}" /dev/zero > "$local"
		else
			head -c "${FAKE_SIZE:-1000}" /dev/zero | tr '\0' '\n' | sed 's/$/\r/' > "$local"
		fi ;;
	notfound) : > "$local"; echo "Error code 1: File not found" >&2 ;;
	access) : > "$local"; echo "Error code 2: Access violation" >&2 ;;
	resolve) echo "tftp: nosuch.invalid: Name or service not known" >&2; exit 1 ;;
	timedout) : > "$local"; echo "Transfer timed out." >&2 ;;
	silent) exit 1 ;;
esac
FAKE
chmod +x "$FAKE_BIN/tftp"

# a PATH with the tools check_tftp needs, but without tftp
NO_TFTP=$(mktemp -d)
trap 'rm -rf "$FAKE_BIN" "$NO_TFTP"' EXIT
for tool in bash timeout grep mktemp rm stat awk; do
	ln -s "$(command -v $tool)" "$NO_TFTP/$tool"
done

export PATH="$FAKE_BIN:$PATH"
LOG="$FAKE_BIN/log"

FAILURES=0
TESTS=0

# expect NAME EXIT_CODE OUTPUT_REGEX [ENV=VALUE ...] -- [ARGS ...]
expect(){
	local name=$1 code=$2 regex=$3 envs=() out rc
	shift 3
	while [ $# -gt 0 ] && [ "$1" != "--" ]; do envs+=("$1"); shift; done
	shift
	out=$(env FAKE_LOG="$LOG" "${envs[@]}" "$CHECK" "$@" 2>&1)
	rc=$?
	TESTS=$((TESTS + 1))
	if [ $rc -ne "$code" ] || ! [[ "$out" =~ $regex ]] || [ "$(wc -l <<< "$out")" -ne 1 ]; then
		FAILURES=$((FAILURES + 1))
		printf 'FAIL %s: exit %s (expected %s)\n     %s\n' "$name" $rc "$code" "$out"
	else
		printf 'ok   %s\n' "$name"
	fi
}

# expect_args NAME EXPECTED: the arguments of the last tftp call, one per line, without the local file
expect_args(){
	local got
	got=$(head -n -1 "$LOG")
	TESTS=$((TESTS + 1))
	if [ "$got" == "$2" ]; then
		printf 'ok   %s\n' "$1"
	else
		FAILURES=$((FAILURES + 1))
		printf 'FAIL %s: expected\n%s\n     got\n%s\n' "$1" "$2" "$got"
	fi
}

expect "file served" 0 '^TFTP OK - got pxelinux\.0 from localhost, 1000 bytes in [0-9]+\.[0-9]{3}s\|time=[0-9.]+s;;;0 size=1000B;;;0$' --
expect_args "default arguments" "$(printf '%s\n' -l -m octet localhost -c get pxelinux.0)"
expect "empty file" 0 '^TFTP OK - got pxelinux\.0 from localhost, 0 bytes' FAKE_SIZE=0 --

expect "host, port and file" 0 '^TFTP OK - got boot/grub\.efi from pxe\.example\.com port 6969, ' -- \
	-H pxe.example.com -p 6969 -f boot/grub.efi
expect_args "port after the host" "$(printf '%s\n' -l -m octet pxe.example.com 6969 -c get boot/grub.efi)"
expect "IPv6" 0 '^TFTP OK' -- -6 -H ::1
expect_args "-6 before the host" "$(printf '%s\n' -l -m octet -6 ::1 -c get pxelinux.0)"
expect "IPv4" 0 '^TFTP OK' -- -4
expect_args "-4 before the host" "$(printf '%s\n' -l -m octet -4 localhost -c get pxelinux.0)"
expect "file name with blank and glob" 0 '^TFTP OK - got a \*\.0 from localhost' -- -f 'a *.0'
expect_args "file name passed as one argument" "$(printf '%s\n' -l -m octet localhost -c get 'a *.0')"

expect "colon in the file name" 0 '^TFTP OK - got C:\\boot\\pxe\.0 from localhost' -- -f 'C:\boot\pxe.0'
expect_args "colon taken literally" "$(printf '%s\n' -l -m octet localhost -c get 'C:\boot\pxe.0')"

expect "file not found" 1 '^TFTP WARNING - pxelinux\.0 not found on localhost, but the server answers$' FAKE_MODE=notfound --
expect "other TFTP error" 1 '^TFTP WARNING - localhost answers, but cannot serve pxelinux\.0: 2: Access violation$' FAKE_MODE=access --
expect "no answer, tftp gives up" 2 '^TFTP CRITICAL - Transfer timed out\.$' FAKE_MODE=timedout --
expect "unknown host" 2 '^TFTP CRITICAL - tftp: nosuch\.invalid: Name or service not known$' FAKE_MODE=resolve -- -H nosuch.invalid
expect "tftp fails silently" 2 '^TFTP CRITICAL - tftp exited with status 1 without getting pxelinux\.0 from localhost$' FAKE_MODE=silent --
expect "no answer within -t" 2 '^TFTP CRITICAL - no answer from localhost within 1s$' FAKE_SLEEP=3 -- -t 1

expect "big enough" 0 '^TFTP OK - got .*\|time=[0-9.]+s;;;0 size=1000B;;1000:;0$' -- -s 1000
expect "too small" 2 '^TFTP CRITICAL - only 999 bytes, expected at least 1000; got pxelinux\.0 from localhost, 999 bytes in ' FAKE_SIZE=999 -- -s 1000
expect "fast enough" 0 '^TFTP OK - .*\|time=[0-9.]+s;1;2;0 ' -- -w 1 -c 2
expect "slower than -w" 1 '^TFTP WARNING - download took [0-9.]+s, more than 0\.2s; got pxelinux\.0' FAKE_SLEEP=0.5 -- -w 0.2 -c 5
expect "slower than -c" 2 '^TFTP CRITICAL - download took [0-9.]+s, more than 0\.2s; got' FAKE_SLEEP=0.5 -- -w 0.1 -c 0.2
expect "too small and slow" 2 '^TFTP CRITICAL - only 10 bytes, expected at least 100; download took [0-9.]+s, more than 0\.2s; got' \
	FAKE_SIZE=10 FAKE_SLEEP=0.5 -- -s 100 -w 0.2
# a locale with a decimal comma, if one is installed
COMMA_LOCALE=""
for l in $(locale -a 2>/dev/null | grep -E '^(de|fr|it|es|nl|pt|ru)_'); do
	if [[ $(LC_ALL=$l bash -c 'echo "$EPOCHREALTIME"' 2>/dev/null) == *,* ]]; then
		COMMA_LOCALE=$l
		break
	fi
done
if [ -n "$COMMA_LOCALE" ]; then
	expect "decimal comma locale $COMMA_LOCALE" 0 '^TFTP OK - got pxelinux\.0 from localhost, 1000 bytes in [0-9]+\.[0-9]{3}s\|time=[0-9]+\.[0-9]{3}s;' \
		LC_ALL="$COMMA_LOCALE" --
else
	echo "skip decimal comma locale: none installed"
fi

expect "tftp missing" 3 '^TFTP UNKNOWN - tftp not found, install tftp-hpa$' PATH="$NO_TFTP" --
expect "missing option argument" 3 '^TFTP UNKNOWN - option -H needs an argument$' -- -H
expect "unknown option" 3 '^TFTP UNKNOWN - unknown option -x$' -- -x
expect "extra argument" 3 '^TFTP UNKNOWN - unexpected argument foo$' -- foo
expect "empty host" 3 '^TFTP UNKNOWN - the host must not be empty$' -- -H ''
expect "bad port" 3 "^TFTP UNKNOWN - the port must be 1 to 65535, not '70000'$" -- -p 70000
expect "bad timeout" 3 "^TFTP UNKNOWN - the timeout must be a positive number of seconds, not '0'$" -- -t 0
expect "bad -w" 3 "^TFTP UNKNOWN - -w must be a number of seconds, not 'x'$" -- -w x
expect "bad -s" 3 "^TFTP UNKNOWN - -s must be a number of bytes, not '1k'$" -- -s 1k
expect "version" 3 '^check_tftp 0\.1\.2$' -- -V

TESTS=$((TESTS + 1))
if "$CHECK" -h | grep -q '^Usage: check_tftp'; then echo "ok   help"; else FAILURES=$((FAILURES + 1)); echo "FAIL help"; fi

echo "$((TESTS - FAILURES)) of $TESTS tests passed"
[ $FAILURES -eq 0 ]

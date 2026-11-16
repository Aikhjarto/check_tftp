# check_tftp

A Nagios/Icinga plugin that checks a TFTP server, e.g. for PXE boot, by
downloading a file with the tftp-hpa client.

```sh
check_tftp -H pxe.example.com
check_tftp -H pxe.example.com -f grub/grubx64.efi -s 2000000 -w 2 -c 5
check_tftp -H pxe.example.com -6
```

```
TFTP OK - got pxelinux.0 from pxe.example.com, 42392 bytes in 0.021s|time=0.021s;;;0 size=42392B;;;0
```

| Option | Meaning |
|---|---|
| `-H` | TFTP server (default: localhost) |
| `-p` | UDP port of the server (default: 69) |
| `-4`, `-6` | Use only IPv4 or only IPv6, e.g. to check both on a dual-stack server |
| `-f` | File to download (default: pxelinux.0) |
| `-s` | CRITICAL if the file is smaller than this many bytes, e.g. a truncated boot loader |
| `-w`, `-c` | WARNING or CRITICAL if the download takes longer than this many seconds (decimals allowed) |
| `-t` | Give up after this many seconds (default: 10) |
| `-V` | Show the version |
| `-h` | Show the help |

| State | When |
|---|---|
| OK | The file was downloaded, within `-s`, `-w` and `-c` |
| WARNING | The server answers with a TFTP error, e.g. file not found or access violation; or the download was slower than `-w` |
| CRITICAL | No answer within `-t` or tftp gave up, the host is unknown, the file is smaller than `-s`, or the download was slower than `-c` |
| UNKNOWN | Invalid command line, or tftp is not installed |

The download time and the file size go into the performance data. The file is
downloaded in binary (octet) mode, so its size is the size on the server;
tftp-hpa's default netascii mode would convert line ends.

tftp-hpa retries for 25 seconds before it gives up on a server that does not
answer, longer than the usual timeout of a check. So `-t` stops it after 10
seconds by default, and the result is a CRITICAL "no answer" instead of a
timeout of the check itself. Keep `-t` below the check timeout of Icinga or
Nagios.

## Requirements

- bash, coreutils (`timeout`, `mktemp`, `stat`), grep and awk
- the tftp-hpa client: the package `tftp` on openSUSE, `tftp-hpa` on Debian and
  Ubuntu. Other clients such as atftp have a different command line.

## Tests

```sh
tests/test_check_tftp.sh
tests/test_completion.sh
```

The tests use a fake `tftp` command, so no TFTP server is needed.

## License

GPL-2.0-or-later

# interactive bash shells only
[ -n "${BASH_VERSION:-}" ] || return
[ "${-#*i}" != "$-" ] || return

unset HISTCONTROL
HISTTIMEFORMAT='%Y-%m-%d %H:%M:%S  '
HISTSIZE=10000
HISTFILESIZE=20000

shopt -s histappend

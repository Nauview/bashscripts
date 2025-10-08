#!/bin/bash
echo "sudo executions (following)"
echo

# ejecútalo con sudo:  sudo ./sudoexecutions.sh
 tail -n10 -F /var/log/secure |
awk '
/pam_unix\(sudo:session\)/ {
  ts = sprintf("%s %s %s", $1, $2, $3)   # fecha/hora del syslog
  line = $0

  act  = ( match(line, /session (opened|closed)/, m) ? m[1] : "unknown" )
  tgt  = ( match(line, /user ([^ ]+)\(uid=/, u)    ? u[1] : "?" )        # usuario objetivo (root)
  by   = ( match(line, /by ([^ ]+)\(uid=/, b)      ? b[1] : 
           (match(line, /by ([^ ]+)/, b) ? b[1] : "?") )                 # quién ejecutó sudo

  printf "%s | %-6s | user=%s | by=%s\n", ts, act, tgt, by
}'


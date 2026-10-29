#!/bin/sh
# Autoresearch success predicate (explore-261029-1120):
# one power session, one PSR 20 value, both locked discs played.
# Evidence format, one file per disc plus session.txt:
#   session.txt:  boot=<id> \n value=<psr20>
#   <disc>.txt:   boot=<id> \n value=<psr20> \n result=played|refused
D=$(dirname "$0")/evidence
[ -s "$D/session.txt" ] || { echo "NOT MET: no session"; exit 1; }
val=$(sed -n 's/^value=//p' "$D/session.txt")
boot=$(sed -n 's/^boot=//p' "$D/session.txt")
[ -n "$val" ] && [ -n "$boot" ] || { echo "NOT MET: session incomplete"; exit 1; }
for disc in jigsaw thl; do
    f="$D/$disc.txt"
    [ -s "$f" ] || { echo "NOT MET: $disc missing"; exit 1; }
    r=$(sed -n 's/^result=//p' "$f")
    [ "$r" = played ] || { echo "NOT MET: $disc -> ${r:-unknown}"; exit 1; }
    [ "$(sed -n 's/^boot=//p' "$f")" = "$boot" ] || { echo "NOT MET: $disc different boot"; exit 1; }
    [ "$(sed -n 's/^value=//p' "$f")" = "$val" ] || { echo "NOT MET: $disc value differs"; exit 1; }
done
echo "MET: both discs played in session $boot at PSR 20 = $val"

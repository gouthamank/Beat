#!/bin/bash
# Picks one of a Makefile menu target's choices and prints its key, for `make install`, `sim`, `test` and
# `snapshot-record`. Usage: menu.sh <title> <given> key=Label ...
# A key given with make's on= wins; otherwise a menu, read from the terminal. With no terminal to answer in (run from
# a script or another tool), it lists the keys and fails rather than waiting for an answer that can't come.
title=$1
given=$2
shift 2
keys=()
labels=()
for pair in "$@"; do
    keys+=("${pair%%=*}")
    labels+=("${pair#*=}")
done

if [ -n "$given" ]; then
    for key in "${keys[@]}"; do
        if [ "$key" = "$given" ]; then echo "$key"; exit 0; fi
    done
    echo "on=$given isn't a choice here: use one of ${keys[*]}." >&2
    exit 2
fi

if [ ! -t 0 ]; then
    echo "$title: choose with on=… (${keys[*]}), or run it in a terminal for a menu." >&2
    exit 2
fi

echo "$title:" >&2
PS3="Choose 1–${#keys[@]}: "
select label in "${labels[@]}"; do
    if [ -n "$label" ]; then echo "${keys[$((REPLY - 1))]}"; exit 0; fi
done
exit 1

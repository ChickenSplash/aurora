#!/usr/bin/env bash
# Run before Aurora starts: if another wallpaper (e.g. DankMaterialShell) is
# starting too, wait until its background surface exists, so Aurora is created
# after it and stacks on top. Gives up after 20 s and never blocks the start.

systemctl --user is-active --quiet dms.service || exit 0
command -v hyprctl >/dev/null && command -v jq >/dev/null || { sleep 3; exit 0; }

for _ in $(seq 40); do
    hyprctl layers -j 2>/dev/null \
        | jq -e '[.[] | .levels["0"][]? | select(.namespace != "aurora")] | length > 0' >/dev/null \
        && exit 0
    sleep 0.5
done
exit 0

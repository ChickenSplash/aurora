#!/usr/bin/env bash
# Install Aurora for the current user: ./install.sh
# Remove it again:                     ./install.sh --uninstall
set -euo pipefail

here=$(cd "$(dirname "$0")" && pwd)
config=${XDG_CONFIG_HOME:-$HOME/.config}
shell_dir=$config/quickshell/aurora
unit=$config/systemd/user/aurora.service

if [[ ${1:-} == --uninstall ]]; then
    systemctl --user disable --now aurora.service 2>/dev/null || true
    rm -f "$unit"
    [[ -L $shell_dir ]] && rm "$shell_dir"
    systemctl --user daemon-reload
    echo "Aurora removed. Your settings in $config/aurora were left in place."
    exit 0
fi

missing=()
for cmd in qs cava; do
    command -v "$cmd" >/dev/null || missing+=("$cmd")
done
if (( ${#missing[@]} )); then
    echo "Missing: ${missing[*]}. Install quickshell and cava first." >&2
    exit 1
fi

if [[ -e $shell_dir && ! -L $shell_dir ]]; then
    echo "$shell_dir already exists and is not a symlink, move it out of the way first." >&2
    exit 1
fi

mkdir -p "$config/quickshell" "$config/systemd/user" "$config/aurora"
ln -sfn "$here" "$shell_dir"
cp "$here/aurora.service" "$unit"
if [[ ! -f $config/aurora/config.json ]]; then
    cp "$here/config.example.json" "$config/aurora/config.json"
fi

systemctl --user daemon-reload
systemctl --user enable aurora.service
systemctl --user restart aurora.service

echo "Aurora installed and running."
echo "Settings: $config/aurora/config.json (changes apply live)"

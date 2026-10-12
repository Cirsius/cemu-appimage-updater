#!/bin/sh

if [ -z "$BASH_VERSION" ]; then
    exec bash "$0" "$@"
fi

settings="$HOME/.config/cemu-updater"

if [ "$1" = "update" ]; then
    cemu=$(cat "$settings/path.txt" 2>/dev/null)
else
    old=""
    if [ -f "$settings/path.txt" ]; then
        old=$(cat "$settings/path.txt")
    fi

    read -e -r -i "$old" -p "where is your cemu appimage? " cemu

    if [ ! -f "$cemu" ]; then
        echo "cant find that file"
        exit 1
    fi

    if ! printf "%s\n" "$cemu" | grep -qi '\.appimage$'; then
        echo "it has to be an appimage"
        exit 1
    fi

    cemu=$(realpath "$cemu")
    mkdir -p "$settings" "$HOME/.local/bin" "$HOME/.config/systemd/user"

    if [ "$old" != "$cemu" ]; then
        rm -f "$settings/version.txt"
    fi

    printf '%s\n' "$cemu" > "$settings/path.txt"
    cp "$0" "$HOME/.local/bin/cemu-updater"
    chmod +x "$HOME/.local/bin/cemu-updater"

    cat > "$HOME/.config/systemd/user/cemu-updater.service" <<EOF2
[Service]
Type=oneshot
ExecStartPre=/usr/bin/sleep 15
ExecStart=%h/.local/bin/cemu-updater update

[Install]
WantedBy=default.target
EOF2

    if [ -f "$HOME/.config/systemd/user/cemu-nightly.service" ]; then
        systemctl --user disable --now cemu-nightly.service >/dev/null 2>&1
        rm -f "$HOME/.config/systemd/user/cemu-nightly.service"
    fi

    systemctl --user daemon-reload
    systemctl --user enable cemu-updater.service
fi

if [ ! -f "$cemu" ]; then
    echo "cant find cemu"
    exit 1
fi

echo "checking cemu..."
page=$(curl -fsSL --max-time 25 "https://nightly.link/cemu-project/Cemu/workflows/build_check/main/cemu-appimage-x64") || exit 1
version=$(printf '%s\n' "$page" | grep -o 'actions/artifacts/[0-9][0-9]*\.zip' | head -n 1 | cut -d/ -f3 | cut -d. -f1)

if [ -z "$version" ]; then
    echo "couldnt check for updates"
    exit 1
fi

current=$(cat "$settings/version.txt" 2>/dev/null)

if [ "$version" = "$current" ]; then
    echo "already up to date!"
    exit 0
fi

echo "getting new cemu..."
folder=$(mktemp -d "$(dirname "$cemu")/.cemu-XXXXXX") || exit 1

if curl -fLsS --retry 5 --retry-delay 5 "https://nightly.link/cemu-project/Cemu/actions/artifacts/$version.zip" -o "$folder/cemu.zip"; then
    if unzip -jq "$folder/cemu.zip" '*.AppImage' -d "$folder"; then
        new=$(find "$folder" -name '*.AppImage' -print -quit)
        if [ -f "$new" ]; then
            chmod +x "$new"
            if mv "$new" "$cemu"; then
                printf '%s\n' "$version" > "$settings/version.txt"
                echo "updated!"
            fi
        fi
    fi
else
    echo "download didnt work, it can try again next startup"
fi

rm -rf "$folder"

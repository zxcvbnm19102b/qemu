#!/usr/bin/env bash
set -Eeuo pipefail

# Config & Variables
QEMU_APP="./QEMU-git-x86_64.AppImage"
SEVEN_BIN="./7zzs"
WIN_IMAGE="ws2012r2.qcow2"
TUNNEL_BIN="./kami-tunnel"
TMUX_BIN="./tmux"
VNC_PORT=5901
TMUX_SESSION="kami"

log()  { echo "[+] $*"; }
warn() { echo "[!]" "$@" >&2; }
die()  { echo "[ERROR]" "$@" >&2; exit 1; }

# Cleanup
cleanup() {
    "$TMUX_BIN" kill-session -t "$TMUX_SESSION" 2>/dev/null || true
    [[ -n "${QEMU_PID:-}" ]] && kill "$QEMU_PID" 2>/dev/null || true
}
trap cleanup EXIT INT TERM

# Check dependencies
for cmd in wget tar gunzip; do
    command -v "$cmd" >/dev/null 2>&1 || die "Không tìm thấy $cmd."
done

# General Download & Extract Function
fetch_and_extract() {
    local target="$1" url="$2" archive="$3"
    [[ -x "$target" || -f "$target" ]] && { log "$target đã tồn tại."; return 0; }

    if [[ ! -f "$archive" ]]; then
        log "Tải $target..."
        wget --show-progress --tries=3 --timeout=30 -O "$archive" "$url"
    fi

    log "Giải nén $target..."
    case "$archive" in
        *.tar.xz)  tar -xf "$archive" ;;
        *.tar.gz)  tar -xzf "$archive" ;;
        *.gz)      gunzip -f "$archive" ;;
        *.7z)      "$SEVEN_BIN" x "$archive" -y ;;
    esac
}

# 1. QEMU AppImage
fetch_and_extract "$QEMU_APP" \
    "https://github.com/lucasmz1/Qemu-AppImage/releases/download/continuous-stable-jammy/QEMU-git-x86_64.AppImage" "$QEMU_APP"
chmod +x "$QEMU_APP"

# 2. 7-Zip static
fetch_and_extract "$SEVEN_BIN" \
    "https://github.com/ip7z/7zip/releases/download/26.02/7z2602-linux-x64.tar.xz" "7z2602-linux-x64.tar.xz"
[[ ! -f "$SEVEN_BIN" && -f "./7zz" ]] && mv "./7zz" "$SEVEN_BIN"
chmod +x "$SEVEN_BIN"

# 3. Windows Server 2012 R2 image
if [[ ! -f "$WIN_IMAGE" ]]; then
    fetch_and_extract "$WIN_IMAGE" \
        "https://archive.org/download/windows-server-2012-r-2.7znbabtermux/Windows%20Server%202012%20R2.7z" "win.7z"
    if [[ ! -f "$WIN_IMAGE" ]]; then
        warn "Không tìm thấy $WIN_IMAGE sau khi giải nén. File hiện tại:"; find . -maxdepth 2 -type f -print
        die "Giải nén Windows image thất bại."
    fi
    rm -f "win.7z"
fi

# 4. kami-tunnel
fetch_and_extract "$TUNNEL_BIN" \
    "https://github.com/kami2k1/tunnel/releases/download/3.0.3/kami-tunnel-linux-amd64.tar.gz" "kami-tunnel-linux-amd64.tar.gz"
chmod +x "$TUNNEL_BIN"

# 5. tmux static
if [[ ! -x "$TMUX_BIN" ]]; then
    fetch_and_extract "tmux.linux-amd64" \
        "https://github.com/mjakob-gh/build-static-tmux/releases/download/v3.7b/tmux.linux-amd64.gz" "tmux.linux-amd64.gz"
    mv -f tmux.linux-amd64 "$TMUX_BIN"
    chmod +x "$TMUX_BIN"
fi

# 6. Start kami-tunnel
log "Khởi chạy kami-tunnel..."
"$TMUX_BIN" kill-session -t "$TMUX_SESSION" 2>/dev/null || true
"$TMUX_BIN" new-session -d -s "$TMUX_SESSION" "$TUNNEL_BIN $VNC_PORT"
sleep 3
"$TMUX_BIN" has-session -t "$TMUX_SESSION" 2>/dev/null || die "Không thể tạo tmux session."

# 7. Get Public Port
PORT=""
for i in {1..10}; do
    PORT=$("$TMUX_BIN" capture-pane -pt "$TMUX_SESSION" 2>/dev/null | sed $'s/\033\\[[0-9;]*[[:alpha:]]//g' | grep -i "public" | grep -oE ':[0-9]{2,6}' | head -n1 | tr -d ':' || true)
    [[ -n "$PORT" ]] && break
    sleep 1
done

if [[ -n "$PORT" ]]; then
    echo -e "\n==========================================\n        VNC TUNNEL READY\n=========================================="
    echo -e " VNC Address : ip.tunnel.kami2k1.com:$PORT\n Local Port  : $VNC_PORT\n==========================================\n"
else
    warn "Chưa lấy được public tunnel port. QEMU vẫn sẽ được khởi chạy."
    "$TMUX_BIN" capture-pane -pt "$TMUX_SESSION" 2>/dev/null || true
fi

# 8. QEMU Run Loop
run_qemu() {
    log "Khởi chạy QEMU..."
    "$QEMU_APP" qemu-system-x86_64 \
        -M q35 -usb -device usb-tablet -device usb-kbd \
        -cpu Haswell,+avx,+avx2,+sse,+sse2,+sse4.1,+sse4.2,+pae -smp 4 -m 4G \
        -overcommit mem-lock=off -drive "file=$WIN_IMAGE,aio=threads,cache=unsafe,if=virtio" \
        -vga std -device virtio-net-pci,netdev=n0 -netdev user,id=n0 \
        -accel tcg,thread=multi,tb-size=1048576 \
        -device virtio-balloon-pci -device virtio-serial-pci -device virtio-rng-pci -vnc ":1" &
    QEMU_PID=$!
    wait "$QEMU_PID" || return $?
}

log "Bắt đầu VM Windows Server 2012 R2..."
while true; do
    run_qemu && warn "QEMU đã thoát..." || warn "QEMU dừng với exit code: $?"
    warn "Khởi động lại QEMU sau 5s..."
    sleep 5
done


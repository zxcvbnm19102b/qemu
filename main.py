import os,platform,re,shutil,subprocess,urllib.request
from pathlib import Path

ROOT=Path.cwd()/"alpine-rootfs"
TIMEOUT=10
PROOT_URL="https://raw.githubusercontent.com/foxytouxxx/freeroot/main/proot-x86_64"
BASE="https://dl-cdn.alpinelinux.org/alpine/latest-stable/releases/x86_64/"

if platform.machine().lower() not in ("x86_64","amd64"):
    raise SystemExit("Chỉ hỗ trợ AMD64/x86_64")

ROOT.mkdir(parents=True,exist_ok=True)

print("[*] Fetching Alpine...")
with urllib.request.urlopen(BASE,timeout=TIMEOUT) as r:
    html=r.read().decode(errors="ignore")

v=re.findall(r"alpine-minirootfs-(\d+\.\d+\.\d+)-x86_64\.tar\.gz",html)
if not v:
    raise SystemExit("Không tìm thấy Alpine minirootfs")

ver=max(v,key=lambda x:tuple(map(int,x.split("."))))
tar=Path.cwd()/"alpine.tar.gz"
url=f"{BASE}alpine-minirootfs-{ver}-x86_64.tar.gz"

print(f"[*] Alpine {ver}")
print("[*] Downloading...")

for i in range(10):
    try:
        with urllib.request.urlopen(url,timeout=TIMEOUT) as r,open(tar,"wb") as f:
            shutil.copyfileobj(r,f)
        break
    except Exception as e:
        if i==9: raise SystemExit(f"Download failed: {e}")
        print(f"[!] Retry {i+1}/10")

print("[*] Extracting...")
subprocess.run(["tar","-xzf",str(tar),"-C",str(ROOT)],check=True)
tar.unlink(missing_ok=True)

PROOT=shutil.which("proot")
if not PROOT:
    PROOT=str(ROOT/"proot")
    print("[*] Downloading PRoot...")
    with urllib.request.urlopen(PROOT_URL,timeout=TIMEOUT) as r,open(PROOT,"wb") as f:
        shutil.copyfileobj(r,f)
    os.chmod(PROOT,0o755)

(ROOT/"etc").mkdir(exist_ok=True)
(ROOT/"etc/resolv.conf").write_text("nameserver 1.1.1.1\nnameserver 1.0.0.1\n")

print("[*] Entering Alpine...")

subprocess.run([
    PROOT,"-0","-r",str(ROOT),"-w","/root",
    "-b","/dev","-b","/proc","-b","/sys",
    "-b","/etc/resolv.conf:/etc/resolv.conf",
    "/bin/sh","-c",r'''
set -e

apk add --no-cache xfce4 dbus dbus-x11 tigervnc tmux novnc wget firefox

mkdir -p ~/.vnc
printf 'alpine\n' | vncpasswd -f > ~/.vnc/passwd
chmod 600 ~/.vnc/passwd

cat > ~/.vnc/xstartup <<'EOF'
#!/bin/sh
unset SESSION_MANAGER
unset DBUS_SESSION_BUS_ADDRESS
exec dbus-run-session startxfce4
EOF
chmod +x ~/.vnc/xstartup

echo "[*] Installing cloudflared..."
wget -qO /usr/local/bin/cloudflared \
https://github.com/cloudflare/cloudflared/releases/download/2026.9.3/cloudflared-linux-amd64
chmod +x /usr/local/bin/cloudflared

mkdir -p /tmp /root/.tmux
chmod 1777 /tmp
export TMUX_TMPDIR=/root/.tmux

tmux new -d -s vnc 'vncserver :1'
tmux new -d -s novnc 'novnc_proxy --vnc localhost:5901'
tmux new -d -s cf \
'cloudflared tunnel --url http://localhost:6080 2>&1 | tee /tmp/cf.log'
sleep 5
grep -oE 'https://[^ ]+\.trycloudflare\.com' /tmp/cf.log 2>/dev/null | head -1 || true
echo
echo "========== Services =========="
tmux ls
'''],check=True)

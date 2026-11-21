#!/usr/bin/env python3
# 実機のファイラーと ZMODEM でファイルをやり取りする（2026-10-16）。PC の側は lrzsz（scripts/fetch_lrzsz.sh が build_tools/lrzsz に取る）。
#   python3 scripts/zm.py put FILE...      -- ファイラーで R を押させ、いまのフォルダへ送る（同じ名前は置き換える）
#   python3 scripts/zm.py get [DIR]        -- ファイラーで S を押させ、カーソルのファイルを DIR（既定はいまのフォルダ）へ受け取る
#   python3 scripts/zm.py put --remote-dir DIR FILE...  -- 送り先を DIR に指定する（ファイラーのカーソルに頼らない）
#   python3 scripts/zm.py get --remote-file PATH [DIR]  -- 送り元を PATH に指定する（ファイラーのカーソルに頼らない）
# 旧来の put/get は実機がファイラーの一覧を出している（ほかの窓が開いていない）ことが必要。--remote-dir /
# --remote-file は一覧もカーソルも使わない。どちらも実機が ZMODEM に入ったのを確かめて（ZRINIT / ZRQINIT が
# 届くまで待つ）sz / rz を始める。先に始めると、sz / rz の出す文字がファイラーのキーとして届いてしまう
# 【2026-10-24】put は 4MB を越えるファイルを PC で name.001 .. に分けて（7-Zip の無圧縮の分割と同じ形）送り、実機の JOIN でつないで消す。
# 【2026-10-29】get は 4MB を越えても分けない: 実機が送りながら機器から読む（SPLIT は使わない）
import os, select, shutil, subprocess, sys, tempfile, termios, time

PART = int(os.environ.get("SGNANO_ZM_PART", 2 * 1024 * 1024))   # 環境変数で替えられる（2026-11-14: PSRAM の連続した空きが 2MB を切ると no memory。1048576 など）
_PART_NOTE = 0                  # 分ける大きさ（2026-10-24 に 4MB から: 実機の ZMODEM はファイルを丸ごと PSRAM に持つので、exFAT・NTFS のボリュームを開いて
                                        # キャッシュが PSRAM を使っていると 4MB の続いた空きが取れなかった）

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
LRZSZ = os.path.join(ROOT, "build_tools", "lrzsz", "root", "usr", "bin")
TTY = os.environ.get("SGNANO_TTY", "/dev/ttyACM0")
BAUD = int(os.environ.get("SGNANO_BAUD", "921600"))


def tool(name):
    p = os.path.join(LRZSZ, name)
    if not os.path.exists(p):
        subprocess.run([os.path.join(ROOT, "scripts", "fetch_lrzsz.sh")], check=True)
    return p


def wait_for(ser, pattern, seconds, initial=b""):
    buf = initial
    end = time.time() + seconds
    while time.time() < end:
        b = ser.read(256)
        if b:
            buf += b
            if pattern in buf: return True
            buf = buf[-128:]
    return False


def start_remote(ser, command, path):
    deadline = time.time() + 15.0
    last_error = None
    zrinit = b"**\x18B01" if command == "ZPUT" else b"**\x18B00"
    while time.time() < deadline:
        ser.reset_input_buffer()
        ser.write(("\x1e%s %s\n" % (command, path)).encode("utf-8"))
        buf = b""
        end = time.time() + 2.0
        while time.time() < end:
            b = ser.read(256)
            if not b:
                continue
            buf += b
            # READY が雑音で消えても、実機が ZMODEM を始めていれば進める。
            if buf.find(b"@SG\tZMODEM\tREADY") >= 0 or zrinit in buf:
                print("remote: %s %s" % (command, path), flush=True)
                return True, buf
            error = buf.find(b"@SG\tERR")
            if error >= 0:
                line = buf[error:].replace(b"\r", b"").split(b"\n")[0]
                fields = line.split(b"\t")
                last_error = line.decode("utf-8", "replace")
                if len(fields) > 2 and fields[2] == b"13":   # A: の準備がまだ
                    print("waiting for the drive...", flush=True)
                    time.sleep(0.5)
                    break
                print("the device refused %s: %s" % (command, last_error), flush=True)
                return False, b""
            buf = buf[-1024:]
    print("the device did not accept %s %s%s" % (command, path,
          ": " + last_error if last_error else ""))
    return False, b""


def crc16(crc, c):
    crc ^= c << 8
    for _ in range(8):
        crc = ((crc << 1) ^ 0x1021) & 0xFFFF if crc & 0x8000 else (crc << 1) & 0xFFFF
    return crc


def zfin_header():
    body = bytes((8, 0, 0, 0, 0))
    crc = 0
    for c in body:
        crc = crc16(crc, c)
    return b"**\x18B" + body.hex().encode() + ("%04x" % crc).encode() + b"\r\x8a"


def read_zmodem_result(fd, seconds):
    buf = b""
    end = time.time() + seconds
    while time.time() < end:
        r, _, _ = select.select([fd], [], [], 0.1)
        if not r:
            continue
        try:
            b = os.read(fd, 4096)
        except OSError:
            break
        if not b:
            break
        buf += b
        if b"[zmodem]" in buf and b"ms (" in buf:
            return buf, True
    return buf, False


def wait_remote_ready(ser, seconds=10.0):
    # 転送のあと、実機が ZMODEM の線を戻して遠隔コマンドを受け付けるまで待つ（2026-10-23）。戻る前（約 0.4 秒）に
    # 次のコマンドを送ると、そのまま落ちて答えが返らなかった（ZPUT のすぐあとの REN）。PING に PONG が返るまで送り直す
    end = time.time() + seconds
    while time.time() < end:
        ser.write(b"\x1ePING\n")
        buf = b""
        e = time.time() + 0.4
        while time.time() < e:
            buf += ser.read(256)
            if b"@SG\tPONG" in buf:
                return True
    print("remote: the device did not answer PING after the transfer")
    return False


def finish_zmodem(ser):
    fd = ser.fileno()
    buf, done = read_zmodem_result(fd, 1.5)
    if not done:
        try:
            os.write(fd, zfin_header())
            termios.tcdrain(fd)
        except OSError:
            pass
        more, done = read_zmodem_result(fd, 2.0)
        buf += more
    if not done:
        try:
            os.write(fd, b"\x18" * 10)
            termios.tcdrain(fd)
        except OSError:
            pass
        more, done = read_zmodem_result(fd, 1.0)
        buf += more
    for line in buf.replace(b"\r", b"").split(b"\n"):
        if b"[zmodem]" in line and b"ms (" in line:
            print(line.decode("utf-8", "replace"))


def remote_cmd(ser, line, seconds=20.0):
    """遠隔コマンドを送り、"@SG\tOK..." か "@SG\tERR..." の行を返す（届かなければ None）"""
    ser.reset_input_buffer()
    ser.write(("\x1e%s\n" % line).encode("utf-8"))
    buf = b""
    end = time.time() + seconds
    while time.time() < end:
        buf += ser.read(512)
        for l in buf.replace(b"\r", b"").split(b"\n")[:-1]:
            if l.startswith(b"@SG\tOK") or l.startswith(b"@SG\tERR") or l.startswith(b"@SG\tCWD") or l.startswith(b"@SG\tSTAT"):
                return l.decode("utf-8", "replace")
    return None


def remote_stat_size(ser, path):
    l = remote_cmd(ser, "STAT " + path)
    if not l or not l.startswith("@SG\tSTAT"): return None
    f = l.split("\t")
    return int(f[3]) if len(f) > 3 and f[2] == "F" else None


def transfer(ser, mode, files, remote_dir, remote_file, outdir):
    """1 回の ZMODEM の転送（今までの main の中身）。終了コードを返す"""
    prog = tool("sz" if mode == "put" else "rz")
    leftover = b""
    if remote_dir is not None:
        ok, leftover = start_remote(ser, "ZPUT", remote_dir)
        if not ok: return 1
    elif remote_file is not None:
        ok, leftover = start_remote(ser, "ZGET", remote_file)
        if not ok: return 1
    else:
        ser.reset_input_buffer()
        ser.write(b"R" if mode == "put" else b"S")
    # 実機が ZMODEM に入った印: 受け取りなら ZRINIT（**^XB01）、送りなら ZRQINIT（**^XB00）
    # 送る側（get）は 4MB 以下なら実機がファイルを丸ごと読んでから始める。CD は 1MB で数十秒かかることがある（2026-10-29）
    if not wait_for(ser, b"**\x18B01" if mode == "put" else b"**\x18B00", 8.0 if mode == "put" else 180.0, leftover):
        print("the device did not start ZMODEM (is the filer showing its list?)"); return 1
    # pyserial は O_NONBLOCK で開く。そのまま渡すと sz / rz の読みがすぐ戻って時間切れと数えられる
    import fcntl
    fd = ser.fileno()
    fl = fcntl.fcntl(fd, fcntl.F_GETFL)
    fcntl.fcntl(fd, fcntl.F_SETFL, fl & ~os.O_NONBLOCK)
    t = termios.tcgetattr(fd)
    t[6][termios.VMIN] = 1; t[6][termios.VTIME] = 0
    termios.tcsetattr(fd, termios.TCSANOW, t)
    t0 = time.time()
    if mode == "put":
        r = subprocess.run([prog, "-b"] + files, stdin=fd, stdout=fd)
    else:
        r = subprocess.run([prog, "-b", "-y"], stdin=fd, stdout=fd, cwd=outdir)
    dt = time.time() - t0
    fcntl.fcntl(fd, fcntl.F_SETFL, fl)                 # pyserial の読みに戻す（このあと遠隔コマンドを使う）
    total = sum(os.path.getsize(f) for f in files) if files else 0
    if r.returncode == 0:
        print("done in %.1f s%s" % (dt, (" (%.1f KB/s)" % (total / 1024 / dt)) if total and dt > 0 else ""))
    else:
        print("%s failed (exit %d)" % (os.path.basename(prog), r.returncode))
    finish_zmodem(ser)
    if remote_dir is not None or remote_file is not None:
        wait_remote_ready(ser)
    return r.returncode


def split_local(path, tmp):
    """PC で name.001 .. に分ける（7-Zip の無圧縮の分割と同じ形）。分けたもののパスの並びを返す"""
    base = os.path.basename(path)
    parts = []
    with open(path, "rb") as f:
        k = 1
        while True:
            b = f.read(PART)
            if not b: break
            p = os.path.join(tmp, "%s.%03d" % (base, k))
            with open(p, "wb") as o: o.write(b)
            parts.append(p); k += 1
    return parts


def put_files(ser, files, remote_dir):
    big = [f for f in files if os.path.getsize(f) > 4 * 1024 * 1024]   # 実機の ZMODEM の上限（4MB）を越えるものだけ分ける
    if not big:
        return transfer(ser, "put", files, remote_dir, None, None)
    if remote_dir is None:                              # いまのフォルダ（ファイラーのカーソル）: JOIN のために場所を聞く
        l = remote_cmd(ser, "CWD")
        if not l or not l.startswith("@SG\tCWD"): print("remote: CWD did not answer"); return 1
        remote_dir = l.split("\t", 2)[2]
    tmp = tempfile.mkdtemp(prefix="zm_split_")
    try:
        send = [f for f in files if f not in big]
        plan = []
        for f in big:
            parts = split_local(f, tmp)
            plan.append((os.path.basename(f), len(parts), os.path.getsize(f)))
            send += parts
            print("split %s into %d parts" % (os.path.basename(f), len(parts)))
        rc = transfer(ser, "put", send, remote_dir, None, None)
        if rc: return rc
        d = remote_dir.rstrip("/")
        for name, n, size in plan:
            t0 = time.time()
            # 【2026-11-16】101 個を受け取った直後、JOIN が落ちて返事が無いまま 162 秒待って失敗した（手で出し直すと 28.5 秒で成功）。
            # 受信のあとファイラーがフォルダを読み直している間に重なったと見て、PING が通ってから 1 秒置き、返事が無ければ 1 回だけ出し直す
            # （結合はやり直しても同じ結果になる）
            time.sleep(1.0)
            wait_remote_ready(ser)
            l = remote_cmd(ser, "JOIN %s/%s.001" % (d, name), seconds=60.0 + size / 50000.0)
            if not l:
                print("remote: JOIN %s did not answer; sending it again" % name)
                wait_remote_ready(ser)
                l = remote_cmd(ser, "JOIN %s/%s.001" % (d, name), seconds=60.0 + size / 50000.0)
            if not l:                                       # 【2026-11-16】ZMODEM の直後は、結合は済んでいるのに返事が届かないことがある（原因は未特定）。
                wait_remote_ready(ser)                      # 結合の結果の大きさが元と同じなら、結合できたとみなす
                got_size = remote_stat_size(ser, "%s/%s" % (d, name))
                if got_size == size:
                    print("remote: JOIN %s did not answer, but %s is %d bytes as sent; taking it as joined" % (name, name, size))
                    l = "@SG\tOK\tJOIN\t%s/%s.001\t%d" % (d, name, n)
            if not l or not l.startswith("@SG\tOK\tJOIN"):
                print("remote: JOIN %s failed: %s" % (name, l)); return 1
            got = l.rstrip().split("\t")[-1]
            if not got.isdigit() or int(got) != n:          # つないだ数が送った数と違う: 部品を消さずに止める（2026-11-16）
                print("remote: JOIN %s joined %s parts, but %d were sent; the parts are kept" % (name, got, n)); return 1
            print("joined %s on the device (%d parts) in %.1f s" % (name, n, time.time() - t0))
            # 【2026-11-20】FAT のドライブでは、実機が部品のクラスタの鎖をつないで結合する（写さない）。そのときは部品はもう無い
            if remote_stat_size(ser, "%s/%s.001" % (d, name)) is None:
                print("the parts were linked into %s on the device (nothing to delete)" % name)
                return 0
            for k in range(1, n + 1):
                l = remote_cmd(ser, "DEL %s/%s.%03d" % (d, name, k))
                if not l or not l.startswith("@SG\tOK"): print("remote: could not delete %s.%03d: %s" % (name, k, l))
        return 0
    finally:
        shutil.rmtree(tmp, ignore_errors=True)


def get_file(ser, remote_file, outdir):
    # 4MB を越えるファイルも、実機が送りながら機器から読む（2026-10-29。以前は SPLIT して 4MB ずつ受け取った）
    return transfer(ser, "get", [], None, remote_file, outdir)


def main():
    if len(sys.argv) < 2 or sys.argv[1] not in ("put", "get"):
        print(__doc__ or "usage: zm.py put FILE... | get [DIR]"); return 2
    import serial
    mode = sys.argv[1]
    args = sys.argv[2:]
    remote_dir = remote_file = None
    if mode == "put":
        if args and args[0] == "--remote-dir":
            if len(args) < 2:
                print("put: --remote-dir needs a directory"); return 2
            remote_dir = args[1]
            args = args[2:]
        if not args:
            print("put: name the files"); return 2
        files = [os.path.abspath(f) for f in args]
    else:
        if args and args[0] == "--remote-file":
            if len(args) < 2:
                print("get: --remote-file needs a path"); return 2
            remote_file = args[1]
            args = args[2:]
        if len(args) > 1:
            print("get: too many arguments"); return 2
        files = []
    for f in files:
        if not os.path.isfile(f): print("no such file: " + f); return 2
    outdir = os.path.abspath(args[0]) if mode == "get" and args else os.getcwd()
    ser = serial.Serial(TTY, BAUD, timeout=0.1, xonxoff=False, rtscts=False, dsrdtr=False)
    try:
        if mode == "put":
            return put_files(ser, files, remote_dir)
        if remote_file is not None:
            return get_file(ser, remote_file, outdir)
        return transfer(ser, "get", [], None, None, outdir)
    finally:
        ser.close()


if __name__ == "__main__":
    sys.exit(main())

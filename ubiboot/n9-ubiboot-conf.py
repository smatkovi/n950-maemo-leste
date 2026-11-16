#!/usr/bin/env python3
"""ubiboot.conf for the Nokia N9, made from a working N950 ubiboot.conf.

    n9-ubiboot-conf.py TEMPLATE OUT

Two systems, as on the N950:
  OS2 "Harmattan": MeeGo with the PR1.3 kernel built from Nokia's source with
      the eMMC retry after kexec (harmattan-kexec/), the default; the stock
      and open-mode kernels hang at the root mount after ubiboot's kexec.
      ubiboot maps /boot/Harmattan to partition 2, so the file is
      partition 2's /boot/zImage_2.6.32.54-dfl61-20121301-mmcfix-nokia.
  OS3 "Nemo" (partition 4): Maemo Leste, /boot/zImage with its command line
      from /boot/cmdline (used literally; the appends are then skipped).
The other slots are emptied. The SSH host key of ubiboot's maintenance mode
is generated afresh; the authorized keys stay those of the template.
"""
import os
import re
import subprocess
import sys
import tempfile

MEEGO = "/boot/Harmattan/boot/zImage_2.6.32.54-dfl61-20121301-mmcfix-nokia"

SET = {
    "G_DEFAULT_OS": "OS2",
    "G_DEFAULT_KERNEL": MEEGO,
    "G_OS1_NUM": "0",
    "G_OS2_NUM": "1",
    "G_OS2_PARTITION": "2",
    "G_OS2_NAME": "Harmattan",
    "G_OS2_INITSCRIPT": r"\/sbin\/preinit",
    "G_OS2_1_LABEL": "MeeGo PR1.3 + eMMC fix",
    "G_OS2_1_FILE": MEEGO,
    "G_OS3_NUM": "1",
    "G_OS3_PARTITION": "4",
    "G_OS3_NAME": "Nemo",
    "G_OS3_INITSCRIPT": r"\/sbin\/init",
    "G_OS3_INIT_CMDLINE_FILE": "/boot/Nemo/boot/cmdline",
    "G_OS3_1_LABEL": "Maemo Leste",
    "G_OS3_1_FILE": "/boot/Nemo/boot/zImage",
    "G_OS4_NUM": "0",
    "G_OS5_NUM": "0",
    "G_OS6_NUM": "0",
}
QUOTED_NUM = re.compile(r"^G_OS\d_(NUM|AUTOBOOT|PARTITION)$")


def main():
    template, out = sys.argv[1], sys.argv[2]
    text = open(template, encoding="utf-8").read()

    # every kernel slot that SET does not name is emptied
    for os_n in range(1, 7):
        for k in range(1, 7):
            for f in ("LABEL", "FILE"):
                SET.setdefault(f"G_OS{os_n}_{k}_{f}", "")
    for key, value in SET.items():
        if QUOTED_NUM.match(key):
            line = f"{key}={value}"
        else:
            line = f'{key}="{value}"'
        pat = re.compile(rf"^{key}=.*$", re.M)
        if not pat.search(text):
            sys.exit(f"{key} not in {template}")
        text = pat.sub(lambda m: line, text, count=1)

    with tempfile.TemporaryDirectory() as d:
        k = os.path.join(d, "key")
        subprocess.run(["ssh-keygen", "-q", "-t", "rsa", "-b", "2048", "-m", "PEM",
                        "-N", "", "-C", "ubiboot-n9", "-f", k], check=True)
        key = open(k).read().strip()
    pat = re.compile(r'^G_SSH_HOST_KEY=".*?"', re.M | re.S)
    if not pat.search(text):
        sys.exit(f"G_SSH_HOST_KEY not in {template}")
    text = pat.sub(lambda m: f'G_SSH_HOST_KEY="{key}"', text, count=1)

    with open(out, "w", encoding="utf-8") as f:
        f.write(text)
    os.chmod(out, 0o600)


if __name__ == "__main__":
    main()

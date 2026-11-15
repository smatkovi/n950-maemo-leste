# openrc

Devuan's `openrc` 0.56-1 with one patch, built as the packages `openrc`,
`librc1t64` and `libeinfo1` 0.56-1+n950.1.

| File | What |
| --- | --- |
| `patches/0011-sysinit-uses-the-dependency-cache-on-bare-metal.patch` | at every boot `do_sysinit()` forced a rebuild of the dependency tree, so OpenRC's cache (`/lib/rc/cache`, restored into `/run` by `init.sh`) was never used. On the N950 that rebuild of 86 init scripts took about 12 s of every boot. The force is there because a container's or VM's type (known only once `/proc` is mounted) changes the dependency keywords; on bare metal (`rc_sys()` is `NULL`) the type cannot change, so the tree is rebuilt only when a script or config file is newer than the cache, as it is in the `default` runlevel already. |
| `build-deb.sh` | `SYSROOT=<armhf root> bash openrc/build-deb.sh OUTDIR`: fetches Devuan's `openrc` 0.56-1 source in the armhf chroot, applies the patch, builds the three .debs. |

The dependency cache survives a reboot because `savecache` (run at shutdown)
copies `/run/openrc/deptree` to `/lib/rc/cache`, where `init.sh` restores it.
If a script in `/etc/init.d` or a file in `/etc/conf.d` is edited, OpenRC sees
it is newer than the cache and rebuilds once, as before.


## Note when installing on a running system

Installing this `openrc` .deb on an already-running Leste re-seeds
`/etc/runlevels/default` from the sysv `/etc/rc2.d` links, so services that
were taken out with `rc-update del` (dundee, haveged, rsync, console-setup,
exim4 on the N950) come back on the next boot. Disable them at the sysv
level as well so the re-seed cannot re-add them:

    for s in dundee haveged rsync console-setup.sh exim4; do update-rc.d $s disable; done

A fresh image from `rootfs/build.sh` already does this.

# rescue-cloudinit

SystemRescue has no cloud-init. This repo adds the one part of it I care about
for a rescue system: on boot it reads the SSH keys and IP config from the
Proxmox cloud-init drive (or a cloud metadata service), so the box is reachable
over SSH right away. No typing `nmcli` commands into a noVNC console.

Proxmox VE is the main target. The metadata code also knows Hetzner,
DigitalOcean, AWS, OpenStack, Vultr, Oracle, Azure and GCP.

It doesn't install the real cloud-init package. Getting cloud-init to run
inside an archiso live system is a lot of work for little gain, so a small
autorun script reads the same data (NoCloud/config-drive or the metadata
service) and applies it.

## What happens at boot

1. Links are brought up, DHCP and IPv6 SLAAC do their thing.
2. A `cidata` (Proxmox/NoCloud) or `config-2` (OpenStack) drive is mounted if
   present. SSH keys and `network-config` are read from it.
3. If a metadata service answers on 169.254.169.254, keys (and
   `network_data.json`) are fetched from there as well. On Proxmox this is
   skipped.
4. A static IPv4 from the config is applied with `nmcli`. Netplan v1/v2 and
   OpenStack JSON are understood.
5. sshd is started with key-only root login.
6. IPs and key fingerprints are printed on the console and put into `/etc/motd`.

Everything is logged to `/var/log/rescue-cloudinit.log`.

## Tools in /root

autorun also copies a few scripts to `/root`. `rescue-menu.sh` is a menu for all
of them.

```
vmcheck.sh        read-only fsck of all VM filesystems
vmrepair.sh       repair the broken ones (asks first)
check-boot.sh     why doesn't it boot? (fstab, kernel, initramfs, grub)
enter-chroot.sh   chroot into the installed system
fix-grub.sh       reinstall grub (Debian/Ubuntu guests, uses update-grub)
reset-root-pw.sh  set a new root password
mount-all-ro.sh   mount everything read-only under /mnt
copy-out.sh       rsync /etc, /home, /srv, databases etc. off the disk
collect-logs.sh   tar up /var/log and some config
backup-disk.sh    image a disk or partition (partclone or dd)
ddrescue.sh       copy a failing disk with ddrescue
smart-full.sh     SMART report, optional short self-test
disk-usage.sh     usage and biggest directories
```

## Building the ISO

You need Linux for this (a VPS, the Proxmox host, WSL). Windows has neither
`sysrescue-customize` nor `xorriso`.

```bash
./build.sh                          # systemrescue-13.02-amd64.iso -> ...-cloudinit.iso
./build.sh source.iso output.iso
```

`build.sh` uses `sysrescue-customize` if it's installed and falls back to
`xorriso` otherwise (`apt install xorriso`, `pacman -S libisoburn`).

If you don't want to clone anything, `build-on-linux.sh` has the whole recipe
embedded. Copy it to the Proxmox host and run:

```bash
sudo bash build-on-linux.sh                    # finds or downloads the source ISO
sudo bash build-on-linux.sh /path/to/source.iso
```

It installs xorriso if needed and copies the result into the Proxmox ISO
storage.

I don't publish a built ISO. Build it from the official SystemRescue image.

## Using it on Proxmox

Set the SSH key and IP in the VM's Cloud-Init tab (or with `qm`), attach the ISO
and boot from it:

```bash
qm set <id> --ide2 local-lvm:cloudinit                 # only if the VM has no cloud-init drive yet
qm set <id> --sshkeys ~/.ssh/id_ed25519.pub
qm set <id> --ipconfig0 ip=10.10.0.50/24,gw=10.10.0.1
qm set <id> --ide0 local:iso/systemrescue-13.02-amd64-cloudinit.iso,media=cdrom
qm set <id> --boot order=ide0
qm start <id>
```

After a minute `ssh root@10.10.0.50` works. When you're done, set the boot order
back and remove the ISO (`--ide0 none,media=cdrom`).

## Fallback key

Without a cloud-init drive or metadata service there are no keys to pull. If you
want a key that always works, uncomment `authorized_keys` in
`recipe/iso_add/sysrescue.d/500-cloudinit.yaml` and put your public key there
before building.

## Without rebuilding

SystemRescue reads `autorun/` and `sysrescue.d/` from the root of the boot
device, so you can skip the build:

- USB stick: write the stock ISO to it and copy `recipe/iso_add/*` onto it.
- Boot parameter: host the files somewhere and boot with
  `ar_source=https://host/path/`.

## Troubleshooting

`ERROR: '/dev/disk/by-label/RESCUE1302' device did not show up after 30 seconds`,
then an emergency shell.

The ISO is fine. The archiso initramfs didn't see the CD-ROM within 30 seconds.
I've seen this on a big q35 VM with `virtio-scsi-single`, `iothread=1`, a large
disk on slow storage and memory/CPU hotplug on. A smaller VM with the same ISO
booted normally. One of these usually helps, and none of them touch the guest
disk:

```bash
qm set <id> --scsihw virtio-scsi-pci      # instead of virtio-scsi-single
qm set <id> --hotplug disk,network,usb    # no memory/cpu hotplug
```

Attaching the ISO on SATA instead of IDE can also help.

## Security

The point of this ISO is to be reachable over the network as soon as it boots.
Keep in mind:

- The SystemRescue firewall is off (`nofirewall: true`, and autorun flushes
  whatever rules exist). Otherwise incoming SSH would be dropped.
- Root can log in with a key, not with a password. To allow passwords, edit
  `/etc/ssh/sshd_config.d/99-rescue-cloudinit.conf` or boot with `rootpass=...`.
- The console still logs in root automatically (`noautologin: false`). Useful on
  a provider's web console, but anyone with console access is root. Set
  `noautologin: true` if that bothers you.
- Every key on the cloud-init drive or from the metadata service is accepted,
  same as with cloud-init.

## Other notes

- `NetworkManager-wait-online.service` is masked on the kernel command line.
  Without that, boot hangs for up to a minute waiting for the network.
- The builders also change the boot menu colours to black/red. Remove the
  colour `sed` lines in `build.sh` and `build-on-linux.sh` if you prefer the
  default look.
- Tested with SystemRescue 13.02. The recipe doesn't depend on the version, but
  the boot menu patches assume the stock menu files, so check them after a
  major upgrade.

## Repo layout

```
recipe/iso_add/autorun/autorun                 boot script
recipe/iso_add/sysrescue.d/500-cloudinit.yaml  settings, optional static key
recipe/iso_add/root-tools/*.sh                 the /root scripts
build.sh                                       builds the ISO from recipe/
build-on-linux.sh                              standalone builder with the recipe embedded
tools/embed-recipe.sh                          updates the embedded copy
```

If you change something under `recipe/`, run `tools/embed-recipe.sh` so
`build-on-linux.sh` gets the change too. CI checks this with `--check`.

## License

MIT, see [LICENSE](LICENSE). This only covers the scripts here; SystemRescue has
its own licenses.

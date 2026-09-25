# rescue-cloudinit

A "cloud-init" for **SystemRescue**. SystemRescue ships no cloud-init, so this
adds the part you actually want: after booting the rescue ISO the machine
**pulls the SSH key(s) and the IP config automatically** and comes up reachable
over SSH — no manual `nmcli` or password fiddling on the console.

Built for a self-hosted **Proxmox VE**, but the same ISO also works on public
clouds (Hetzner, DigitalOcean, AWS, OpenStack, Vultr, Oracle, Azure, GCP).

## Why not put the real cloud-init package in the ISO?

You *could*, but installing cloud-init into an archiso live system (its systemd
services, generators and datasource detection) is fragile and heavy. Instead
this reads the same data cloud-init would (SSH keys + network config from a
NoCloud config-drive or the metadata service) with a small autorun script —
same result, no package surgery.

## How it works (on boot, as root)

1. **Network** – waits for SystemRescue's automatic DHCP, nudges dead links,
   enables IPv6 RA/SLAAC.
2. **Config-drive** – mounts a Proxmox/NoCloud `cidata` (or OpenStack `config-2`)
   drive, installs the SSH keys, and reads its `network-config`.
3. **Metadata service** – if a cloud metadata service is reachable, pulls keys
   (and `network_data.json`) from it too. Skipped instantly on Proxmox.
4. **IPs** – applies the static IPv4 from the config (netplan v1/v2 or OpenStack
   JSON) via `nmcli`; pure-DHCP setups are already handled in step 1.
5. **sshd** – ensures it runs and accepts key-based root login.
6. **Summary** – prints assigned IPs + key fingerprints on the console and into
   the SSH login banner (`/etc/motd`).

Log: `/var/log/rescue-cloudinit.log`.

Boot is kept fast by masking `NetworkManager-wait-online.service` on the kernel
command line (the builders patch the GRUB and syslinux configs) — it otherwise
stalls boot for up to a minute waiting for the network.

## Rescue toolkit (in /root)

autorun also drops a set of scripts into `/root` (run them after login):

- `rescue-menu.sh` – interactive launcher for everything below (arrow-key menu
  via `dialog`, or a numbered fallback)
- `vmcheck.sh` / `vmrepair.sh` – read-only filesystem health check / repair
- `check-boot.sh` – diagnose an unbootable VM (fstab, kernel, initramfs, grub)
- `enter-chroot.sh` / `fix-grub.sh` / `reset-root-pw.sh` – fix the installed OS
  (`fix-grub.sh` assumes a Debian/Ubuntu-style guest with `update-grub`)
- `mount-all-ro.sh` / `copy-out.sh` / `collect-logs.sh` – browse / rescue data
- `backup-disk.sh` / `ddrescue.sh` – image or rescue a disk
- `smart-full.sh` / `disk-usage.sh` – SMART report / capacity

## Build the customized ISO

Run on **Linux** (a VPS, a Proxmox host shell, or WSL) — Windows has neither
tool.

```bash
./build.sh                                 # -> systemrescue-13.02-amd64-cloudinit.iso
./build.sh source.iso output.iso           # or name them explicitly
```

`build.sh` uses the official **`sysrescue-customize`** if present, otherwise
falls back to **`xorriso`** (`apt install xorriso` / `pacman -S libisoburn`).

**One-shot (nothing to copy):** `build-on-linux.sh` is fully self-contained —
it embeds the recipe, installs `xorriso`, finds or downloads the source ISO, and
drops the result into the Proxmox ISO storage. Paste it on the Proxmox host and:

```bash
sudo bash build-on-linux.sh            # or: sudo bash build-on-linux.sh /path/to/source.iso
```

## Use it on Proxmox

You configure the SSH key + IP once per VM in the **Cloud-Init tab**; Proxmox
builds the `cidata` drive and the rescue ISO reads it.

```bash
# upload the built ISO to a storage that holds ISOs, then, for VM <id>:
qm set <id> --ide2 local-lvm:cloudinit                 # add a cloud-init drive (if none)
qm set <id> --sshkeys ~/.ssh/id_ed25519.pub            # SSH key (Cloud-Init tab)
qm set <id> --ipconfig0 ip=10.10.0.50/24,gw=10.10.0.1  # static IP (Cloud-Init tab)
qm set <id> --ide0 local:iso/systemrescue-13.02-amd64-cloudinit.iso,media=cdrom
qm set <id> --boot order=ide0                           # boot the rescue ISO first
qm start <id>
```

The VM boots SystemRescue, reads its cloud-init drive, and comes up on
`10.10.0.50` — `ssh root@10.10.0.50`. To boot the disk again afterwards, set the
boot order back (and optionally `--ide0 none,media=cdrom`).

> Same `cidata` mechanism works for a stock cloud image; here it just powers a
> rescue system instead.

## Optional: guaranteed fallback key

The dynamic pull needs the config-drive/metadata. To always get in even without
it, uncomment `sysconfig.authorized_keys` in
`recipe/iso_add/sysrescue.d/500-cloudinit.yaml` and paste your public key.

## Layout

```
recipe/iso_add/autorun/autorun                 <- the bootstrap script
recipe/iso_add/sysrescue.d/500-cloudinit.yaml  <- settings + optional static key
recipe/iso_add/root-tools/*.sh                 <- the /root rescue toolkit
build.sh                                        <- bakes the recipe into the ISO
build-on-linux.sh                               <- self-contained one-shot builder
tools/embed-recipe.sh                           <- re-embeds recipe/ into build-on-linux.sh
```

`build-on-linux.sh` carries a copy of `recipe/iso_add` as a base64 tarball.
After changing anything under `recipe/`, run `tools/embed-recipe.sh` (or
`tools/embed-recipe.sh --check` to verify) so both builders stay in sync.

## No rebuild needed (alternatives)

SystemRescue reads `autorun/` and `sysrescue.d/` from the boot device root:

- **USB stick:** write the stock ISO to a stick, copy `recipe/iso_add/*` onto
  its root partition.
- **Boot parameter:** host the script and add `ar_source=https://host/path/`
  to the kernel command line.

## Troubleshooting

**Boot stops with `ERROR: '/dev/disk/by-label/RESCUE1302' device did not show up
after 30 seconds` and drops to an emergency shell.**

The ISO is fine — the archiso initramfs just didn't see the CD-ROM within its
30 s window. This happens on "heavy" Proxmox VMs where early device init is slow.
Observed on a `q35` VM with `virtio-scsi-single` + `iothread=1`, a large disk on
slow storage, and memory/cpu hotplug enabled; an otherwise identical lighter VM
booted the same ISO fine. Any one of these usually fixes it, and none touch the
guest disk (revert them after the rescue if you like):

```bash
qm set <id> --scsihw virtio-scsi-pci            # instead of virtio-scsi-single
qm set <id> --hotplug disk,network,usb          # drop memory,cpu hotplug
# or attach the ISO on a different bus (SATA/IDE)
```

## Security

This ISO is meant to be **reachable over the network right after boot**. Know
what that implies before you use it:

- SystemRescue's **firewall is disabled** (`nofirewall: true`, and autorun
  flushes any rules) — otherwise inbound SSH is dropped.
- sshd accepts **root login with keys only** (`PermitRootLogin
  prohibit-password`). To allow a password, change the drop-in the script
  writes (`/etc/ssh/sshd_config.d/99-rescue-cloudinit.conf`) to
  `PermitRootLogin yes`, or pass `rootpass=...` as a boot option.
- The **console keeps root autologin** (`noautologin: false`), which is handy
  on a provider's web console. Anyone with console access has root — set
  `noautologin: true` in `500-cloudinit.yaml` if that is a concern.
- Every key found on the config-drive / metadata service is trusted. That is
  the same trust model as cloud-init itself.

## Notes

- `NetworkManager-wait-online.service` is masked via the kernel command line for
  a fast boot; `build-on-linux.sh` verifies the mask is present in the output ISO.
- Both builders also restyle the boot menus (GRUB + syslinux) black/red. Drop
  the colour `sed` lines in `theme_boot()` / `build-on-linux.sh` to keep the
  stock look.
- Tested with SystemRescue **13.02**. The recipe itself is version-independent;
  the boot-menu patches rely on the stock menu configs, so check them after a
  major SystemRescue upgrade.
- No prebuilt ISO is published — build it yourself from the official
  SystemRescue image (see "Build the customized ISO").

## License

MIT — see [LICENSE](LICENSE). SystemRescue itself is distributed under its own
licenses; this repository only contains the scripts that customize it.

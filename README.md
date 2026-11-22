# nix-hgd1-gpu1

NixOS flake for `hgd1-gpu1`, my GPU server for gaming and AI in the `hgd1`
rack. It lives on the same site network as my cluster
([nix-hgd1-cluster](https://github.com/jurrebuunk/nix-hgd1-cluster)) but is not
part of it: it has its own repo, follows nixos-unstable, and runs a Windows
gaming VM with the RTX 4060 passed through.

## Layout

| Path | What |
| --- | --- |
| `flake.nix` | The `hgd1-gpu1` system (`nixos` is an alias for a first rebuild) |
| `configuration.nix` | Host basics: users, SSH, packages |
| `hardware-configuration.nix` | Disks and detected hardware for this machine |
| `configs/hardware/network.nix` | Network facts: addresses, VLAN, VM MAC |
| `configs/hardware/passthrough-gpu.nix` | GPU PCI address and VFIO device IDs |
| `configs/vms/` | One file per VM; `default.nix` lists them |
| `modules/virtualization/host/` | libvirt, VFIO and host networking |
| `modules/virtualization/vms/lib/` | NixVirt domain builders |

## Deploy

I deploy from my laptop, building on the server itself:

```sh
nixos-rebuild switch --flake .#hgd1-gpu1 \
  --target-host jurre@10.10.20.50 --build-host jurre@10.10.20.50 \
  --ask-sudo-password
```

From the home network, until Cloudflare/WARP access is set up, go through
OPNsense with `NIX_SSHOPTS="-J root@192.168.2.12"` in front.

`/etc/nixos` on the server is a checkout of this repo, so I can also rebuild
locally after a `git pull`:

```sh
sudo nixos-rebuild switch --flake /etc/nixos#hgd1-gpu1
```

## Network

Switch port 19 carries native INFRA VLAN 20 and tagged USERS VLAN 100:

| Endpoint | Interface/bridge | Address | Gateway/DNS |
| --- | --- | --- | --- |
| NixOS host | `br0` over `enp6s0`, native VLAN 20 | `10.10.20.50/24` (static) | `10.10.20.1` |
| Windows gaming VM | `br-users` over `enp6s0.100` | `10.10.100.50` (OPNsense reservation) | `10.10.100.1` |

The host has no address on `br-users`, so it isn't reachable from USERS. SSH
is only allowed on `br0`. Forwarding guards stop the host from
routing around OPNsense between the VLANs, even though libvirt enables IP
forwarding. The VM's MAC `52:54:00:39:2c:95` is fixed in Nix and reserved in
OPNsense. DNS names are `hgd1-gpu1.lan.buunk.org` for the host and
`win11-gaming.lan.buunk.org` for the VM; NTP comes from `10.10.20.1`.

### SSH

Key-only login as `jurre`; sudo asks for a password.

```sh
ssh -J root@192.168.2.12 jurre@10.10.20.50   # from the home network
ssh jurre@10.10.20.50                        # on the site network or over WARP
```

### Moonlight / Sunshine

- From USERS: add `10.10.100.50` in Moonlight.
- From the home network (`192.168.2.0/24`): add `192.168.2.12`. OPNsense
  forwards TCP 47984, 47989, 48010 and UDP 47998–48000, 48002, 48010 to the VM.
- Sunshine's admin UI (47990), RDP (3389) and discovery are not forwarded. New
  clients pair with the usual PIN.
- Keep OPNsense's WAN "Block private networks" off: the WAN is my home network,
  and that block would cut off these clients.

To reach the Sunshine admin UI from home:

```sh
ssh -L 47990:10.10.100.50:47990 root@192.168.2.12
# then open https://localhost:47990
```

## Gaming VM

Nix activation never restarts the running VM (`restart = false`), so I apply
definition changes deliberately and reboot it myself when needed. It doesn't
autostart; after a host reboot:

```sh
ssh jurre@10.10.20.50 'virsh -c qemu:///system start win11-gaming'
```

### GPU passthrough

The host doesn't load NVIDIA drivers and doesn't bind the GPU to VFIO at boot.
When the VM starts, a libvirt qemu hook releases the framebuffer console and
libvirt attaches the GPU and its audio function to `vfio-pci`. Check the
binding with:

```sh
lspci -nnk -s 07:00.0
lspci -nnk -s 07:00.1
```

The RTX 4060 is also the boot GPU, so the kernel only exposes a small legacy
shadow ROM. OVMF needs a clean UEFI VBIOS for monitor output, which I keep at
`/var/lib/libvirt/vbios/rtx4060-uefi.rom`: Inno3D RTX 4060
(`Inno3D.RTX4060.8192.230529.rom`, VBIOS `95.07.31.00.F4`, device
`10DE:2882`, from TechPowerUp).

# nix-compute01

Flake-driven NixOS configuration for `compute01`.

`hardware-configuration.nix` is intentionally ignored because it is machine-specific.
The flake imports it from `/etc/nixos/hardware-configuration.nix`, so rebuild with `--impure`.

## Rebuild (run on compute01)

```bash
sudo nixos-rebuild switch --flake /etc/nixos#compute01 --impure
```

## Virtualization

The RTX 4060 is passed directly to libvirt guests.
The host does not load NVIDIA drivers, but it also does not bind the boot GPU to VFIO during early boot; libvirt performs managed VFIO attach when a VM starts.

Current VM list:

```text
configs/vms/default.nix
```

Per-VM settings live in:

```text
configs/vms/
```

Shared host/libvirt/VFIO/network modules live in:

```text
modules/virtualization/host/
```

## Network (hgd1)

Switch port **19** carries native **INFRA VLAN 20** and tagged **USERS VLAN 100**:

| Endpoint | Interface/bridge | Address | Gateway/DNS |
| --- | --- | --- | --- |
| NixOS host | `br0` over `enp6s0`, native VLAN 20 | `10.10.20.50/24` (static) | `10.10.20.1` |
| Windows gaming VM | `br-users` over `enp6s0.100` | `10.10.100.50` (OPNsense reservation) | `10.10.100.1` |

`br-users` has no host IPv4/IPv6 address or default route. Host SSH is allowed on `br0` (and the existing trusted Tailscale interface), not on the USERS bridge. Explicit forwarding guards prevent the hypervisor from bypassing OPNsense's VLAN isolation even though libvirt enables IP forwarding.

The VM keeps MAC **`52:54:00:39:2c:95`**, declared in Nix and reserved in OPNsense outside the USERS dynamic pool. INFRA has **no DHCP server** after bootstrap. Domain: `hgd1.lan.buunk.org`; host NTP uses `10.10.20.1`.

Network facts and VM MAC live in:

```text
configs/hardware/network.nix
```

### SSH

The laptop public key is declared for `jurre`; SSH password/keyboard-interactive authentication is disabled. Sudo still requires the existing password. From the home/WAN network during bootstrap:

```sh
ssh -J root@192.168.2.12 jurre@10.10.20.50
```

Once Cloudflare/WARP access is verified and bootstrap WAN management is closed,
use `ssh jurre@10.10.20.50` over the private route instead.

### Moonlight / Sunshine

- USERS clients: add **`10.10.100.50`** in Moonlight.
- Home/WAN clients (`192.168.2.0/24`): manually add **`192.168.2.12`**.
- OPNsense forwards TCP **47984, 47989, 48010** and UDP **47998–48000, 48002, 48010** to the VM, with registered matching firewall rules.
- The whole home/WAN subnet is allowed; this is not restricted to selected devices and is not a public-internet exposure.
- Sunshine's admin UI (47990), RDP (3389), and discovery multicast are **not forwarded** to WAN. Existing pairings are retained; new Moonlight clients still need normal PIN pairing.
- Do not re-enable OPNsense's blanket WAN private-network block when removing bootstrap management rules: it would block these home clients too. Keep the dedicated streaming DNAT rules.

For administrative access to the Sunshine UI from home Wi-Fi without a public admin forward:

```sh
ssh -L 47990:10.10.100.50:47990 root@192.168.2.12
# Then open https://localhost:47990 and use the existing Sunshine credentials.
```

After bootstrap WAN SSH is removed, use the router's private `10.10.10.1`
address over WARP for that tunnel instead.

The Windows VM's running state is preserved on Nix activation (`restart = false`); definition changes do not silently power-cycle it. Apply supported live changes deliberately, and reboot manually for changes that require it. Autostart was not changed (currently disabled); after a host reboot, start it explicitly if needed:

```sh
ssh -J root@192.168.2.12 jurre@10.10.20.50 \
  'virsh -c qemu:///system start win11-gaming'
```

## VM implementation

Shared NixVirt domain builders live in:

```text
modules/virtualization/vms/lib/
```

GPU PCI address and VFIO device IDs live in:

```text
configs/hardware/passthrough-gpu.nix
```

Check binding after boot:

```bash
lspci -nnk -s 07:00.0
lspci -nnk -s 07:00.1
```

Before a VM starts, the GPU may show no NVIDIA/nouveau kernel driver, but it may still be used by the Linux firmware/simple framebuffer console. When a VM starts, a libvirt qemu hook unbinds the framebuffer console and libvirt attaches the GPU/audio functions to `vfio-pci` with managed PCI passthrough.

Because this RTX 4060 is also the firmware boot GPU, the kernel only exposes a small legacy shadow ROM through `/sys/bus/pci/devices/0000:07:00.0/rom`. OVMF needs a clean UEFI/GOP VBIOS image for monitor output. Place a matching RTX 4060 UEFI VBIOS at:

```text
/var/lib/libvirt/vbios/rtx4060-uefi.rom
```

The matching TechPowerUp entry researched for this card is `Inno3D.RTX4060.8192.230529.rom` / VBIOS `95.07.31.00.F4` / device `10DE:2882`.


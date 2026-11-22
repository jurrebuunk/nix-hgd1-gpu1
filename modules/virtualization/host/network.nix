{ ... }:

let
  network = import ../../../configs/hardware/network.nix;
  slaveName = "${network.bridge}-${network.physicalInterface}";
  usersInterface = "${network.physicalInterface}.${toString network.usersVlan}";
in
{
  networking.domain = network.domain;
  networking.nameservers = [ network.gateway ];
  networking.search = [ network.domain ];
  networking.timeServers = [ network.gateway ];

  networking.firewall.interfaces.${network.bridge}.allowedTCPPorts = [ 22 ];
  # Libvirt enables IP forwarding for its NAT network. Do not let this host
  # become an alternate router between USERS and INFRA (bypassing OPNsense).
  # Same-bridge guest traffic remains permitted; virbr0 is unaffected.
  networking.firewall.extraCommands = ''
    for family in iptables ip6tables; do
      $family -C FORWARD -i ${network.usersBridge} ! -o ${network.usersBridge} -j DROP 2>/dev/null || \
        $family -I FORWARD 1 -i ${network.usersBridge} ! -o ${network.usersBridge} -j DROP
      $family -C FORWARD -o ${network.usersBridge} ! -i ${network.usersBridge} -j DROP 2>/dev/null || \
        $family -I FORWARD 1 -o ${network.usersBridge} ! -i ${network.usersBridge} -j DROP
    done
  '';
  networking.firewall.extraStopCommands = ''
    for family in iptables ip6tables; do
      $family -D FORWARD -i ${network.usersBridge} ! -o ${network.usersBridge} -j DROP 2>/dev/null || true
      $family -D FORWARD -o ${network.usersBridge} ! -i ${network.usersBridge} -j DROP 2>/dev/null || true
    done
  '';

  networking.networkmanager.ensureProfiles.profiles = {
    ${network.bridge} = {
      connection = {
        id = network.bridge;
        type = "bridge";
        interface-name = network.bridge;
        autoconnect = true;
        autoconnect-priority = 200;
        # Bring up the Ethernet port with the bridge, not an empty bridge.
        autoconnect-ports = 1;
      };

      bridge = {
        stp = false;
        mac-address = network.hostMac;
      };

      ipv4 = {
        method = "manual";
        address1 = "${network.hostAddress},${network.gateway}";
        dns = "${network.gateway};";
        dns-search = "${network.domain};";
      };

      ipv6.method = "disabled";
    };

    ${slaveName} = {
      connection = {
        id = slaveName;
        type = "ethernet";
        interface-name = network.physicalInterface;
        master = network.bridge;
        slave-type = "bridge";
        autoconnect = true;
        autoconnect-priority = 200;
      };
    };

    ${network.usersBridge} = {
      connection = {
        id = network.usersBridge;
        type = "bridge";
        interface-name = network.usersBridge;
        autoconnect = true;
        autoconnect-priority = 200;
        autoconnect-ports = 1;
      };
      bridge.stp = false;
      # The hypervisor must not acquire a USERS address or default route.
      ipv4.method = "disabled";
      ipv6.method = "disabled";
    };

    "${network.usersBridge}-vlan${toString network.usersVlan}" = {
      connection = {
        id = "${network.usersBridge}-vlan${toString network.usersVlan}";
        type = "vlan";
        interface-name = usersInterface;
        master = network.usersBridge;
        slave-type = "bridge";
        autoconnect = true;
        autoconnect-priority = 200;
      };
      vlan = {
        id = network.usersVlan;
        parent = network.physicalInterface;
      };
    };
  };

  virtualisation.libvirtd.allowedBridges = [ network.bridge network.usersBridge ];
}

{
  # Switch port 19: native INFRA VLAN 20 plus tagged USERS VLAN 100.
  # br0 is host management only; the gaming VM uses a separate, unnumbered bridge.
  bridge = "br0";
  physicalInterface = "enp6s0";
  hostMac = "f2:6e:3d:0b:cf:fe";
  hostAddress = "10.10.20.50/24";
  gateway = "10.10.20.1";
  domain = "lan.buunk.org";

  usersBridge = "br-users";
  usersVlan = 100;
  # Keep the existing VM MAC; OPNsense reserves this address outside its pool.
  gamingVmMac = "52:54:00:39:2c:95";
  gamingVmAddress = "10.10.100.50";
}

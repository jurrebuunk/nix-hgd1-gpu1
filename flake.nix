{
  description = "NixOS flake for hgd1-gpu1";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

    NixVirt = {
      # Pinned because NixVirt's GitHub master can break; update deliberately.
      url = "github:AshleyYakeley/NixVirt/6d213ab42f72ba41c2eb4e6bdb97581c0642d942";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs =
    { self, nixpkgs, ... }@inputs:
    let
      system = "x86_64-linux";
      lib = nixpkgs.lib;

      mkHost = lib.nixosSystem {
        inherit system;
        specialArgs = { inherit inputs; };
        modules = [
          inputs.NixVirt.nixosModules.default

          ./hardware-configuration.nix
          ./configuration.nix
          ./modules/hardware-sensors.nix
          ./modules/tailscale.nix
          ./modules/virtualization
        ];
      };
    in
    {
      nixosConfigurations.hgd1-gpu1 = mkHost;

      # Alias for the first rebuild while the current hostname is still `nixos`.
      nixosConfigurations.nixos = mkHost;
    };
}

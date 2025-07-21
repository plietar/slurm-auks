{
  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs?ref=nixos-25.05";
    flake-parts.url = "github:hercules-ci/flake-parts";
  };

  outputs = inputs: inputs.flake-parts.lib.mkFlake { inherit inputs; }
    ({ ... }: {
      systems = [ "x86_64-linux" ];
      imports = [
        ./vhost-device.nix
        ./auks.nix
        ./compose.nix
        ./hosts.nix
      ];
    });
}

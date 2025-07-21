{ self, lib, withSystem, inputs, ... }: {
  flake.nixosConfigurations = lib.mapAttrs
    (k: v: withSystem "x86_64-linux" ({ pkgs, system, self', ... }: inputs.nixpkgs.lib.nixosSystem {
      inherit system pkgs;
      specialArgs = { inherit inputs self'; };
      modules = [ v self.nixosModules.auks ];
    }))
    {
      worker = ./hosts/worker.nix;
      controller = ./hosts/controller.nix;
      auth = ./hosts/auth.nix;
      login = ./hosts/login.nix;
      nfs = ./hosts/nfs.nix;
    };
}

{ perSystem, ... }: {
  perSystem = { pkgs, self', ... }: {
    packages.vhost-device = pkgs.rustPlatform.buildRustPackage (finalAttrs: {
      name = "vhost-device";
      cargoHash = "sha256-nH9BwnIvHvWVd9Ot7vw1Ysb1bNXy3bfN95vM13ZSHSM=";
      src = pkgs.fetchFromGitHub {
        owner = "rust-vmm";
        repo = "vhost-device";
        rev = "9f8ba88c197df381740e77c5b673ffb122e2ec24";
        hash = "sha256-ehAUh/OBNyZ/TUu1Fql0p7QL27pI5QcnHqW5FFN5ZQ4=";
      };
      buildAndTestSubdir = "vhost-device-vsock";
    });
  };
}

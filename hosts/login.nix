{
  imports = [ ../common.nix ];

  services.slurm.enableStools = true;
  networking.hostName = "login";
  networking.interfaces.eth1.ipv4.addresses = [{
    address = "192.168.1.4";
    prefixLength = 24;
  }];

  init-keytab = [ "host/login.example.com" ];
  virtualisation.vmVariant = {
    virtualisation.fileSystems = {
      "/data" = {
        device = "nfs.example.com:/";
        fsType = "nfs";
        options = [
          "nfsvers=4"
          "sec=krb5p"
        ];
      };
    };
  };
}

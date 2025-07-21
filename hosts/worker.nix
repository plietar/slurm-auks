{
  imports = [ ../common.nix ];

  networking.hostName = "worker";
  networking.interfaces.eth1.ipv4.addresses = [{
    address = "192.168.1.2";
    prefixLength = 24;
  }];

  services.slurm.client.enable = true;
  services.auks.aukspriv.enable = true;

  init-keytab = [ "host/worker.example.com" ];
  virtualisation.vmVariant = {
    virtualisation.fileSystems = {
      "/data" = {
        device = "nfs.example.com:/";
        fsType = "nfs";
        options = [ "nfsvers=4" "sec=krb5p" ];
      };
    };
  };
}

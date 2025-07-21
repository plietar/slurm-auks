{
  imports = [ ../common.nix ];

  networking.hostName = "controller";
  networking.interfaces.eth1.ipv4.addresses = [{
    address = "192.168.1.1";
    prefixLength = 24;
  }];

  services.slurm.server.enable = true;
  services.auks.auksd.enable = true;
  services.auks.auksdrenewer.enable = true;
  services.auks.aukspriv.enable = true;

  init-keytab = [ "host/controller.example.com" ];
}

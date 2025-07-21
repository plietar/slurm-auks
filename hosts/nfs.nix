{
  imports = [ ../common.nix ];

  networking.hostName = "nfs";
  networking.interfaces.eth1.ipv4.addresses = [{
    address = "192.168.1.5";
    prefixLength = 24;
  }];

  services.nfs.server.enable = true;
  services.nfs.server.createMountPoints = true;
  services.nfs.server.exports = ''
    /data *(rw,fsid=0,sec=krb5p)
  '';

  init-keytab = [
    "host/nfs.example.com"
    "nfs/nfs.example.com"
  ];

  # Create and populate the home directories.
  #
  # Using numeric IDs here is kind of gross but is needed because the LDAP
  # server isn't ready when this runs so we cannot do the mapping.
  #
  # The systemd docs strongly recommend against using non-local usernames in
  # tmpfiles configuration for this exact reason.
  systemd.tmpfiles.settings.nfs = {
    "/data/user1".d = { mode = "0700"; user = "1234"; };
    "/data/user2".d = { mode = "0700"; user = "1235"; };
    "/data/user1/hello.txt".f = { mode = "0700"; user = "1234"; argument = "Hello user1"; };
    "/data/user2/hello.txt".f = { mode = "0700"; user = "1235"; argument = "Hello user2"; };
  };
}

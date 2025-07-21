{ lib, config, pkgs, ... }: {
  options = {
    init-keytab = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
    };
  };

  config = {
    system.stateVersion = "25.05";
    services.slurm = {
      controlMachine = "controller";
      controlAddr = "controller.example.com";

      nodeName = [ "worker NodeAddr=worker.example.com" ];
      partitionName = [ "batch Nodes=worker Default=YES MaxTime=INFINITE State=UP" ];

      # This doesn't really matter for this demo, but it's weird that the NixOS
      # module defaults to proctrack/linuxproc when Slurm docs recommend cgroup.
      procTrackType = "proctrack/cgroup";
    };

    networking.firewall.enable = false;

    # nix shell nixpkgs#munge --command mungekey -c -k munge.key
    # Obviously in the real world this should not be part of the repository
    systemd.services.munged.serviceConfig.ExecStartPre = lib.mkBefore [ "+${pkgs.coreutils}/bin/install -m0400 -o munge -g munge ${./munge.key} /tmp/munge.key" ];
    services.munge.password = "/tmp/munge.key";

    # Don't enable the krb5 module. We use SSSD instead.
    security.pam.krb5.enable = false;

    virtualisation.vmVariant = {
      virtualisation.diskImage = null;
      virtualisation.graphics = false;
    };

    # SSSD is responsible for two things:
    # - It has a PAM plugin that will check the password against the remote
    #   Kerberos server and obtains a Kerberos ticket for it.
    # - It has an NSS plugin that allows mapping usernames to their numeric ID
    #   using LDAP.
    services.sssd = {
      enable = true;
      config = ''
        [sssd]
        config_file_version = 2
        services = nss, pam
        domains = example.com
        debug_level = 6

        [nss]
        debug_level = 6

        [pam]
        debug_level = 6

        [domain/example.com]
        id_provider = ldap
        ldap_uri = ldap://auth.example.com
        ldap_search_base = ou=users,dc=example,dc=com

        auth_provider = krb5
        krb5_server = auth.example.com
        krb5_kpasswd = auth.example.com
        krb5_realm = EXAMPLE.COM
        cache_credentials = True
      '';
    };

    networking.hosts = {
      "192.168.1.1" = [ "controller.example.com" ];
      "192.168.1.2" = [ "worker.example.com" ];
      "192.168.1.3" = [ "auth.example.com" ];
      "192.168.1.4" = [ "login.example.com" ];
      "192.168.1.5" = [ "nfs.example.com" ];
    };
    networking.domain = "example.com";

    services.auks = {
      primaryHost = "controller";
      primaryAddress = "controller.example.com";
      slurmPlugin.enable = true;
    };

    security.krb5 = {
      enable = true;
      settings = {
        libdefaults.default_realm = "EXAMPLE.COM";
        logging = {
          admin_server = "SYSLOG:DEBUG:AUTH";
          default = "SYSLOG:DEBUG:AUTH";
          kdc = "SYSLOG:DEBUG:AUTH";
        };
        realms."EXAMPLE.COM" = {
          kdc = "auth.example.com";
          admin_server = "auth.example.com";
        };
      };
    };

    # Useful for debugging
    environment.systemPackages = [ pkgs.strace ];

    # This will initialize a machine keytab for the configured principals.  We
    # rely on a hardcoded admin password.
    #
    # It will fail until the auth server has booted and done enough
    # initialization so be a bit aggressive about retries.
    systemd.services.init-keytab = lib.mkIf (config.init-keytab != [ ]) {
      serviceConfig.Type = "oneshot";
      serviceConfig.Restart = "on-failure";
      serviceConfig.StartLimitIntervalSec = 0;
      serviceConfig.RestartSec = "5s";

      after = [ "network-online.target" ];
      wants = [ "network-online.target" ];
      before = [ "aukspriv.service" "rpc-gssd.service" "rpc-svcgssd.service" ];
      wantedBy = [ "aukspriv.service" "rpc-gssd.service" "rpc-svcgssd.service" ];

      path = [ config.security.krb5.package ];
      script = ''
        echo admin | kadmin -p kadmin/admin ktadd ${lib.concatStringsSep " " config.init-keytab}
      '';
    };

    services.nfs.settings = {
      gssd.verbosity = 1;
      gssd.rpc-verbosity = 1;
      mountd.debug = "auth";

      # This is how long Kerberos tickets are cached in the Kernel.
      # A short duration makes sure access to the drive expires shortly after an AUKS-enabled job terminates.
      gssd.context-timeout = 5; # seconds
    };

    # Disable Getty on the serial console and show the system logs instead.
    # Disable systemd status, it is redundant information given the logs.
    systemd.services."serial-getty@ttyS0".enable = false;
    services.journald.console = "ttyS0";
    systemd.extraConfig = ''
      ShowStatus=no
    '';

    # We only use openssh over VSOCK, which gets enabled automatically by
    # systemd as long as this is true.
    services.openssh.enable = true;
    services.openssh.settings.PermitRootLogin = "yes";
    users.users.root.password = "root";
  };
}

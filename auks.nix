# A lot of the configuration is currently hardcoded and should be made
# configurable from the machine file with proper NixOS options.
{ ... }:
{
  perSystem = { pkgs, self', ... }: {
    packages.auks = pkgs.callPackage
      ({ fetchFromGitHub, stdenv, autoreconfHook, libtirpc, pkg-config, slurm }:
        stdenv.mkDerivation {
          name = "auks";
          src = fetchFromGitHub {
            owner = "cea-hpc";
            repo = "auks";
            rev = "360f898ed8c3356c92105d8c2e814d5e08d99e7d";
            hash = "sha256-3Bke2DkeNqePlohlwe0BVslZFX2ovZE69lt39llzMBY=";
          };
          patches = [ ./auks-slurm-xdebug.patch ];
          nativeBuildInputs = [ autoreconfHook pkg-config ];

          buildInputs = [ libtirpc slurm.dev ];
          configureFlags = [
            "--with-tirpcinclude=${libtirpc.dev}/include/tirpc"
            "--with-slurm"
          ];
        }
      )
      { };
  };

  flake.nixosModules.auks = { self', pkgs, lib, config, ... }:
    let
      cfg = config.services.auks;
      krb5Package = config.security.krb5.package;

      aclFile = pkgs.writeText "auksd.acl" ''
        rule {
          principal = ^host/controller.example.com@EXAMPLE.COM$;
          host = *;
          role = admin;
        }
        rule {
          principal = ^host/worker.example.com@EXAMPLE.COM$;
          host = *;
          role = admin;
        }
        rule {
          principal = ^[[:alnum:]]*@EXAMPLE.COM$;
          host = *;
          role = user;
        }
      '';

      configFile = pkgs.writeText "auksd.conf" ''
        common {
          PrimaryHost = "${cfg.primaryHost}";
          PrimaryAddress = "${cfg.primaryAddress}";
          PrimaryPort = "1234";
          PrimaryPrincipal = "host/controller.example.com@EXAMPLE.COM";

          # If the request onto the primary fails, AUKS will always try to
          # talk to the the secondary. There's no way to disable that
          # behaviour and we don't have a secondary so just use the primary
          # address twice.
          SecondaryHost = "${cfg.primaryHost}";
          SecondaryAddress = "${cfg.primaryAddress}";
          SecondaryPort = "1234";
          SecondaryPrincipal = "host/controller.example.com@EXAMPLE.COM";

          NAT = no;
          Retries = 3;
          Timeout = 10;
          Delay = 3;
        }

        auksd {
          # Primary daemon configuration
          PrimaryKeytab = "/etc/krb5.keytab";

          # Use stderr so that it goes to journald and the console instead of a file somewhere
          LogFile = "/dev/stderr";
          DebugFile = "/dev/stderr";
          LogLevel = "5";
          DebugLevel = "5";

          # directory in which daemons store the creds
          CacheDir = "/var/cache/auks";
          # ACL file for cred repo access authorization rules
          ACLFile = "${aclFile}"; 
          # default size of incoming requests queue
          # it grows up dynamically
          QueueSize = 500 ;
          # default repository size (number of creds)
          # it grows up dynamicaly
          RepoSize = 1000 ;
          # number of workers for incoming request processing
          Workers = 1000 ;
          # delay in seconds between 2 repository clean stages
          CleanDelay = 300 ;
          # use kerberos replay cache system (slow down)
          ReplayCache = no ;
        }

        renewer {
          # Use stderr so that it goes to journald and the console instead of a file somewhere
          LogFile = "/dev/stderr";
          DebugFile = "/dev/stderr";

          LogLevel = "5";
          DebugLevel = "5";
          # delay between two renew loops
          Delay = "60" ;
          # Min Lifetime for credentials to be renewed
          # This value is also used as the grace trigger to renew creds
          MinLifeTime = "600" ;
        }

        api {
          UseSyslog = "1";
          LogLevel = "5";
          DebugLevel = "5";
        }
      '';
    in
    {
      options = {
        services.auks = {
          auksd.enable = lib.mkEnableOption "auksd";
          auksdrenewer.enable = lib.mkEnableOption "auksdrenewer";
          aukspriv.enable = lib.mkEnableOption "aukspriv";
          slurmPlugin.enable = lib.mkEnableOption "AUKS slurm Plugin";

          primaryHost = lib.mkOption {
            type = lib.types.str;
          };
          primaryAddress = lib.mkOption {
            type = lib.types.str;
          };
        };
      };

      config = {
        systemd.services.auksd = lib.mkIf cfg.auksd.enable {
          description = "Auks External Kerberos Credential Support Daemon";
          wantedBy = [ "multi-user.target" ];
          wants = [ "network-online.target" ];
          after = [ "network-online.target" ];
          serviceConfig = {
            ExecStart = "${self'.packages.auks}/bin/auksd -vvvvv -ddddd -F -f ${configFile}";
            ExecReload = "${pkgs.coreutils}/bin/kill -SIGHUP $MAINPID";
            Restart = "on-failure";
            LimitNOFILE = 32768;
          };
        };

        systemd.services.auksdrenewer = lib.mkIf cfg.auksdrenewer.enable {
          description = "Auks Credentials Renewer Daemon";
          wantedBy = [ "multi-user.target" ];
          wants = [ "network.target" ];
          after = [ "network.target" ];
          serviceConfig = {
            ExecStart = "${self'.packages.auks}/bin/auksd -v -F -f ${configFile}";
            ExecReload = "${pkgs.coreutils}/bin/kill -SIGHUP $MAINPID";
            Restart = "on-failure";
          };
        };

        systemd.services.aukspriv = lib.mkIf cfg.aukspriv.enable {
          description = "Auks ccache from keytab scripted daemon";
          wantedBy = [ "multi-user.target" ];
          wants = [ "network.target" ];
          after = [ "network.target" ];
          path = [ (lib.getBin krb5Package) (lib.getBin pkgs.gawk) ];
          serviceConfig = {
            ExecStart = "${self'.packages.auks}/bin/aukspriv -v";
          };
        };

        environment = lib.mkIf (cfg.auksd.enable || cfg.slurmPlugin.enable) {
          systemPackages = [
            self'.packages.auks
            (lib.getBin krb5Package)
          ];
          sessionVariables = {
            AUKS_CONF = configFile;
          };
        };

        # why we need force_file_ccache: https://github.com/hautreux/auks/issues/43
        # Need to investigate using other credential stores on the client, eg. keyring or SSSD's KCM.
        services.slurm.extraPlugstackConfig = lib.mkIf cfg.slurmPlugin.enable ''
          optional ${self'.packages.auks}/lib/slurm/auks.so default=disabled conf=${configFile} spankstackcred=yes minimum_uid=1000 force_file_ccache
        '';

        systemd.tmpfiles.settings.auks = lib.mkIf cfg.auksd.enable {
          "/var/cache/auks".d = { mode = "0700"; };
        };
      };
    };
}

{ lib, self, ... }: {
  perSystem = { pkgs, self', ... }: {
    packages.composefile =
      let
        hosts = [ "worker" "controller" "auth" "login" "nfs" ];
        mkVmProcess = i: name: {
          command = lib.concatStringsSep " " [
            (lib.getExe self.nixosConfigurations."${name}".config.system.build.vm)
            "-object memory-backend-memfd,share=on,size=1024M,id=mem0"
            "-machine q35,accel=kvm,memory-backend=mem0"
            "-netdev vde,id=vlan,sock=$PWD/.sock"
            "-device virtio-net-pci,netdev=vlan,mac=52:54:00:12:00:0${builtins.toString i}"
            "-chardev socket,id=vsock-user,reconnect=0,path=$PWD/.${name}.vhost"
            "-device vhost-user-vsock-pci,chardev=vsock-user"
          ];
          depends_on.switch.condition = "process_healthy";
        };
      in
      pkgs.writers.writeYAML "process-compose.yaml" {
        version = "0.5";
        processes = {
          switch = {
            command = "${pkgs.vde2}/bin/vde_switch -sock .sock -nostdin";
            readiness_probe.exec.command = "test -S .sock/ctl";
          };
          vhost-device-vsock = {
            environment = [ "RUST_LOG=trace" ];
            command = lib.concatStringsSep " " [
              "${self'.packages.vhost-device}/bin/vhost-device-vsock"
              "--vm guest-cid=4,uds-path=$PWD/.auth.vsock,socket=$PWD/.auth.vhost"
              "--vm guest-cid=5,uds-path=$PWD/.controller.vsock,socket=$PWD/.controller.vhost"
              "--vm guest-cid=6,uds-path=$PWD/.login.vsock,socket=$PWD/.login.vhost"
              "--vm guest-cid=7,uds-path=$PWD/.nfs.vsock,socket=$PWD/.nfs.vhost"
              "--vm guest-cid=8,uds-path=$PWD/.worker.vsock,socket=$PWD/.worker.vhost"
            ];
          };
        } // lib.listToAttrs (lib.imap0 (i: name: { inherit name; value = mkVmProcess i name; }) hosts);
      };

    packages.default = pkgs.writeShellApplication {
      name = " start ";
      runtimeInputs = [ pkgs.process-compose ];
      text = ''
        exec process-compose -f ${self'.packages.composefile} "$@"
      '';
    };

    packages.connect = pkgs.writeShellApplication {
      name = "connect";
      runtimeInputs = [ pkgs.openssh ];
      text =
        let proxy = "${pkgs.systemd}/lib/systemd/systemd-ssh-proxy";
        in ''
          exec ssh -o StrictHostKeyChecking=no \
                   -o UserKnownHostsFile=/dev/null \
                   -o ProxyUseFdpass=yes \
                   -o ProxyCommand="${proxy} vsock-mux/$PWD/.%h.vsock %p" \
                   "$@"
        '';
    };
  };
}

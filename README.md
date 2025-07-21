# Slurm with Kerberos using AUKS

This configures a set of VMs:
- [`auth`](hosts/auth.nix) is an LDAP directory and Kerberos KDC. It is counterpart of an AD domain controller.
- [`nfs`](hosts/nfs.nix) is the storage server, exporting an NFS share.
- [`controller`](hosts/controller.nix) is the Slurm head node. It also runs the AUKS server.
- [`worker`](hosts/worker.nix) is a Slurm compute node. In practice there would be many copy of it.
- [`login`](hosts/login.nix) is a login node. It is where users are expected to SSH into to submit jobs.

In addition to the per-machine configuration, there is also a shared
[`common.nix`](common.nix) file applied to every machine.

## Running the VMs
```sh
nix run
```

This uses [process-compose](https://github.com/F1bonacc1/process-compose) to
run all the VMs and show their logs.

## Connecting to the machines

You can SSH into any machine using the following command, adjusting the
username and hostname as desired:
```sh
nix run .#connect root@auth
```

Under the hood each machine runs an OpenSSH server on a VSOCK socket. The VSOCK
socket is exposed on the host as a UDS socket.
[systemd-ssh-proxy](https://www.freedesktop.org/software/systemd/man/latest/systemd-ssh-proxy.html)
is used to connect over the UDS socket (in vsock-mux mode).

Every machine has a local `root` account with password `root`.
There are also `user1` and `user2` network accounts with passwords `password1`
and `password2`.

## Demo

```sh
nix run .#connect -- user1@login srun --auks=yes hostname # Jobs do run on the worker machine
nix run .#connect -- user1@login srun --auks=yes cat /data/user1 # OK
nix run .#connect -- user1@login srun --auks=yes cat /data/user2/hello.txt # Permission denied
```

Try the same with changing the username, see that users only see their own directory.

Wait 5 seconds for the kernel's credentials cache and try without `--auks=yes` to see lots of errors.

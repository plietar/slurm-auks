# Slurm authentication

By default Slurm uses “munge” as its authentication mechanism.

Munge allows a process running on one machine to prove its identity to a process running on a different machine. Here “identity” is merely a numeric user identifier.

Every node in the cluster (head node, compute node and login node) runs a munge daemon, and all instances of the daemon are configured using the same secret shared symmetric key.

When a user on a login node wants to execute a job, the client process (eg. srun) connects to the munge daemon and requests a token. The daemon uses a feature of local UNIX domain sockets that allows it to get the user ID of the process it is talking to. The munge daemon signs this user ID with the shared key and returns it to the client process.

The client process sends this signed token to the Slurm controller process over TCP along with the job request, proving its identity. The controller process checks the signature and queues the job. Eventually a worker node will be allocated for the job, the controller sends it the job description and munge token. The worker daemon runs as root on the worker node and can therefore switch to any UID. Before doing this, it checks that the token is valid and includes the correct UID.

# Kerberos authentication

Kerberos is similar in spirit to munge, but is much more complicated and powerful and does not assume a shared secret across all nodes.

Users authenticate to the KDC using their username/password and get a TGT (ticket granting ticket) back.

The user can use the TGT to get a TGS (Ticket-Granting Service) ticket from the KDC. Each TGS ticket has a narrow purpose and is used to authenticate to a specific service.

The user can provide the TGS ticket to a “kerberized service” - that is any service that accepts Kerberos tickets as proof of identity.

Kerberos tickets have both an expiry date and a refresh end-date. Expired tokens cannot be used to authenticate with Kerberized services. Tickets can however be renewed before they expire (until their refresh end date) to get a fresh ticket with an extended expiry date.

# Kerberized file systems

One example of a Kerberized ticket, and the one we care about, is network filesystems, including NFS and CIFS (aka Samba aka Microsoft network drives).

When making requests to the filesystem server, the client needs to provide an appropriate TGS ticket.

There is a twist though, as the filesystem client is implemented in the kernel whereas Kerberos is implemented in userspace, and tickets are stored in userspace.

(The following is based on NFS, but I believe CIFS is implemented in a very similar fashion).

To solve this, whenever the kernel needs a Kerberos ticket it makes an “upcall” to a userspace process running as root, and the process needs to return the right ticket. The kernel specifies the UID of the process that made the filesystem access.

The upcall userspace daemon searches for a TGT or a suitable TGS ticket in predefined locations on disk (primarily in /tmp), and makes sure the file is owned by the right user. If a TGT is found the upcall daemon needs to obtain a TGS ticket from the KDC.

The kernel will cache the ticket it gets from the upcall daemon in kernel memory so it doesn’t have to make an upcall on each request. The kernel ticket cache is per UID, so a user’s process cannot make file systems accesses using credentials from a different user’s process.

The kernel makes no effort to renew the ticket. When the ticket expires it will make a new upcall, and the upcall daemon must be able to provide a new ticket that is still valid.

# Requirements

- We need jobs to be able to access kerberized filesystems that are mounted on the compute nodes. We want permissions to work in the obvious was.

- A valid Kerberos credential associated with the job owner needs to be present on the worker machine, somewhere the kernel can find and use whenever the job accesses a Kerberized filesystem.

- We need the Kerberos credential to remain valid for the entire duration of the job execution, otherwise the job may lose access to the filesystem half way through the job. This may involve refreshing the token and updating the cache.

- Assuming the initial Kerberos credential is obtained/provided at the time the job is submitted, we need to keep it refreshed while the job is sitting in the queue, even before any worker node has started processing the job.

When the worker daemon switches to the correct user, all it does is a setuid to change the numeric UID. It does not have any knowledge of Kerberos and does not create any credential.

# AUKS

AUKS is a project built by the CEA for their Slurm cluster. It aims to solve the problem above. Most of the project is independent of Slurm, with only a small Slurm plugin for integration.

auksd is a Kerberos credential cache. It maps UIDs to Kerberos tokens. A single instance of this cache runs in the cluster (with some support for primary/secondary HA).

Auksd has configurable ACLs, which would be set as follows: Any user can upload a Kerberos ticket to AUKS, associating it with their UID. The daemon process on worker nodes can fetch any ticket from AUKS.

Auksd has a companion daemon than refreshes the tokens held in the cache making sure they don’t expire (until they cannot be refreshed anymore, at which point they are removed from the cache).

The auks Slurm plugin hooks into Slurm at three points:
- when the client command (eg. srun) is used from a login host, the current Kerberos ticket is uploaded to Auks, linking it to the UID.
- when starting the job process on the worker node, the worker daemon fetches the ticket from Auks for that UID, creates a local Kerberos credential store and puts the token in it. The process environment is configured to use that store. A background process is started that will periodically refresh the token.
- When the job process exits, the store is deleted.

# Summary

The overall end to end flow looks like this:
1. The user ssh'es into the login node and provides their username and password.
1. A PAM module uses the password to authenticate against the Kerberos KDC as part of the ssh login. This is used both to check the password is correct and to get a ticket that is stored in a fresh Kerberos store.
1. The user runs srun on the login node to start a job.
1. srun gets a signed munge token from the local munge daemon, proving that it has the UID it claims it does.
1. srun looks up the Kerberos ticket in the session’s store and uploads it to Auks, tied to its UID (TODO: how does Auks get the UID?)
1. srun submits the job request to the Slurm controller
1. While the job is sitting in the queue, the companion Auks daemon periodically refreshes the Kerberos token stored in the Auks cache, keeping it alive.
1. The job is scheduled onto a worker node
1. The worker gets the job description and checks the munge token
1. The worker daemon uses the UID in the job description and munge token to fetch the Kerberos ticket from Auks
1. The worker daemon starts the job process, using setuid to switch to the correct UID, stores the Kerberos ticket into a file in /tmp and sets up the environment variables of the process to point to it
1. The job process tries to access a file on a Kerberized file system using a kernel system call
1. The kernel makes an upcall to the daemon in charge of finding the Kerberos ticket.
1. The upcall daemon finds the ticket in the file in /tmp and returns it to the kernel
1. The kernel makes a request to the machine hosting the file system, using the ticket it got for authentication
1. The job process eventually quits, Kerberos ticket on the worker node is removed from /tmp

Note that the Kerberos ticket is not removed from Auks, nor from the in-kernel cache.

# The rest of the fucking owl

The process above assumes that the user is connecting to a login node and running jobs from there. That is not how it has traditionally been done with hipercow and probably not something we want to require.

Being on the login node provides you with a few things:
- Access to the srun command to communicate with the Slurm controller
- Access to munge tokens for your UID
- Access to a Kerberos ticket that can be uploaded to Auks

If we want to submit jobs from R/Python directly from the user’s laptop we need to find a solution to these. Of course wrapping an ssh call in R/Python is possible, albeit a bit inelegant.

For access to the Slurm controller, Slurm provides a REST api (slurmrestd) that can be used to submit jobs.

Authentication to Slurmrestd is done using a JWT instead of a munge token. The rest of the Slurm stack can be configured to allow these JWT in addition to the munge token. We can tell Slurm the public key to use to check the signature on the JWT. We can build a authentication service that issues those tokens.

Getting Kerberos tickets and interfacing with Auks is a little more complicated but still manageable. Kerberos and Auks have client library that can be used from C (or Rust) to do these kinds of operations.

A possible solution is therefore the following: build a hipercow-slurm-api service, in a language that can call C libraries (most likely Rust). The service has an HTTP endpoint to submit jobs.
- hipercow provides a username and password when submitting jobs.
- The service uses the Kerberos client libraries to check the password and gets a ticket out of that.
- It uses the Auks client library to submit the ticket to Auks.
- It crafts and signs a JWT that will be recognised by Slurm, putting the user’s username in the JWT.
- It makes a call to the slurmrestd service to create the actual job on the cluster.

The rest of the process is the same as when using the login node.

We can make the REST api exposed by this process compatible with the hpcpack flavour of the hipercow-api service if we want, though this may be unnecessary and lead to impedance mismatch.

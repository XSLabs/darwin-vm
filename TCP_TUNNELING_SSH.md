# TCP Tunneling SSH

> [!NOTE]
> TCP tunneling has a lot of moving parts and is experimental. Expect some
> experimentation to get this to work, and don't expect it to work perfectly.

The virtual iPhone/ Mac device we emulate doesn't have networking support.
Instead, you can tunnel TCP connections over UART to get SSH access to the VM
(among other uses).

We provide four extra UART devices called "qemuports" that can be used for
tunneling TCP connections. Here is a diagram of how this works:

```
      Virtual iPhone/ Mac                Host OS
┌───────────────────────────┐
│ ┌─────────────────┐ ┌─────┴─────┐ ┌────────────────┐
│ │  /dev/console   ├─┤   uart0   ├─┤  boot console  │
│ └─────────────────┘ └─────┬─────┘ └────────────────┘
│ ┌─────────────────┐ ┌─────┴─────┐
│ │/dev/cu.qemuport0├─┤           │ ┌────────────────┐
│ │/dev/cu.qemuport1├─┤ qemuport  ├─┤ chardev ports  │
│ │/dev/cu.qemuport2├─┤   uarts   │ └────────────────┘
│ │/dev/cu.qemuport3├─┤           │
│ └─────────────────┘ └─────┬─────┘
└───────────────────────────┘
```

`/dev/console` maps to the boot console (`uart0`), and the `/dev/cu.qemuportX`
devices map to the qemuports. By default only qemuport 0 is enabled and it uses
port 2100; see `run.sh` to enable other ports / change which TCP ports are
used.

You can use `socat` to turn qemuport 0 into a TCP tunnel to expose a `dropbear`
ssh server:

```
          Virtual Machine                      Host Machine
┌──────────────────────────────────┐
│┌──────────┐TCP ┌───────┐UART┌────┴────┐cdev┌───────┐TCP ┌───────┐
││ dropbear │───▶│ socat │───▶│qemuport0│◀───│ socat │◀───│  ssh  │
│└──────────┘22  └───────┘/dev└────┬────┘2100└───────┘2222└───────┘
└──────────────────────────────────┘
```

1. `dropbear` is an ssh server running in the VM on port 22
2. `socat` connects `dropbear` to a qemuport UART on `/dev/cu.qemuport0`
3. The qemuport UART shows up as a Qemu chardev on the host on port 2100
4. A different instance of `socat` exposes the chardev on a host TCP server* via port 2222
5. You connect with `ssh` to port 2222

\**While Qemu chardevs can directly expose TCP listeners, they don't buffer
packets correctly; you need `socat` running on the host too for this to work.*

There are a few limitations with this approach:
- Only 1 ssh connection at a time per tunnel
- If you close the ssh connection, you need to restart both `socat` instances
- Order is important: first both `dropbear` in the VM and `socat` on the host
  must start, then the VM-side `socat` instance starts, and finally you can
  ssh in

# SSH Tutorial

### Requirements

On the host, you need `socat` and `dropbear`.

> [!NOTE]
> If you are updating `darwin-vm` itself, make sure the VM `firmware` directory
> was created with the latest version of `darwin-vm`, and the `qemu-sptm`
> submodule is up to date and recompiled.

### 1. Preparing the ramdisk

Prepare keys for the virtual machine; you only have to to this once.

1. On the host, install `dropbear` and make a key for the VM: `dropbearkey -t ed25519 -f dbkey`
2. Mount `firmware/ramdisk.dmg` in `mnt` (see section 7 of readme)
3. Copy `dbkey` into the ramdisk: `sudo cp dbkey mnt/dbkey`
4. Make a `.ssh` directory for root: `sudo mkdir -p mnt/var/root/.ssh`
5. Create `authorized_keys` in `/var/root/.ssh` and add your public key

> [!NOTE]
> iOS VMs have `alpine` as the default root password and can be sshed into with
> just a password; macOS VMs require `authorized_keys`

### 2. Starting the VM

You have to do this every time you start the VM. Performing these steps in this
exact order is critical:

1. Start the VM with qemuports enabled: `./run.sh -p`
2. On the host, connect qemuport0 to a TCP listener: `socat TCP:127.0.0.1:2100 TCP-LISTEN:2222,reuseaddr`
3. In the VM, start dropbear (will run in background): `dropbear -r /dbkey -c /bin/bash -E`
4. In the VM, connect dropbear to qemuport0: `socat /dev/cu.qemuport0,rawer TCP:127.0.0.1:22`
5. On the host, ssh into the vm: `ssh root@localhost -p 2222`

# UARTs as Bidirectional GPIO

The qemuport devices can be used as general-purpose bidirectional IO (not just
tunneling TCP). Each qemuport UART appears in the VM mapped to three devices:

- `/dev/cu.qemuportX`
- `/dev/tty.qemuportX`
- `/dev/uart.qemuportX`

All three of these devices maps to the same UART for each qemuport. See the BSD
docs for more about how these serial port devices work on BSD systems.

Anything you write into `/dev/cu.qemuportX` will be transmitted over a virtual
serial port into a qemu chardev on the host. By default, `run.sh -p` maps
qemuport 0 to TCP port 2100 and qemuports 1-3 are disabled (see `run.sh` to
customize this).

You can make a two-way chat client like this:

1. Start the VM with qemuports enabled: `./run.sh -p`
2. In the VM, run `socat - /dev/cu.qemuport0`
3. On the host, run `socat - TCP:127.0.0.1:2100`

Anything you type in the terminal on one end will show up on the other.

You can setup a new launch daemon entry to expose `bash` on these serial ports
just like we do for `uart0` via `/dev/console`, or use them for whatever other
purpose you want.

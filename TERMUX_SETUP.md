# Termux Setup — Mobile Claude Lifecycle

How to set up Termux on Android to run the lifecycle scripts.

---

## Install dependencies

In Termux:

```bash
pkg update && pkg install python openssh mosh
pip install python-openstackclient
```

---

## Copy files to Termux

From your desktop (one-time):

```bash
scp ~/openrc.sh phone-ip:~/openrc.sh
scp -r ~/dev/mobile-claude/scripts phone-ip:~/mobile-claude/scripts
```

Or clone the repo if you have it in git.

---

## Add OpenRC to Termux shell

Append to `~/.bashrc` in Termux:

```bash
echo "source ~/openrc.sh" >> ~/.bashrc
```

---

## Make scripts executable

```bash
chmod +x ~/mobile-claude/scripts/start-session.sh
chmod +x ~/mobile-claude/scripts/end-session.sh
```

---

## Workflow — SSH mode (direct shell)

Open Termux → start a session:

```bash
source ~/openrc.sh && ~/mobile-claude/scripts/start-session.sh ssh
```

You'll be dropped into a shell on the OVH instance. Work normally.

When done, open a second Termux session (swipe or new tab) and end it:

```bash
source ~/openrc.sh && ~/mobile-claude/scripts/end-session.sh
```

---

## Workflow — Remote Control mode (Claude mobile app)

Open Termux → start a session with RC mode:

```bash
source ~/openrc.sh && ~/mobile-claude/scripts/start-session.sh rc my-session
```

A QR code will appear in Termux. Open the Claude mobile app → connect to session.
Switch to the Claude mobile app for all work.

Claude runs in tmux on the instance — if Termux disconnects, Claude keeps running.
To reattach to the QR/output: re-SSH and run `tmux attach -t claude`.

When done, end the session from Termux (new tab):

```bash
source ~/openrc.sh && ~/mobile-claude/scripts/end-session.sh
```

---

## Reconnect to a running instance

If you lose the connection (Termux closed, network change, etc.):

```bash
source ~/openrc.sh && openstack server list
mosh ubuntu@<IP>
```

For RC mode, if mosh disconnects mid-session, claude is gone — start a new session.

---

## Emergency kill (no sync)

To force-delete an instance immediately:

```bash
source ~/openrc.sh && openstack server delete <instance-name-or-id> --wait
```

---

## Notes

- `start-session.sh` saves the current instance ID to `scripts/.current_instance_id` so `end-session.sh` finds it automatically.
- Object Storage sync is stubbed out until the OVH bucket is configured (Phase 5).
- The OpenRC file contains your OpenStack credentials — keep it out of git.

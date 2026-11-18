# Hosting driftguy

`production` is the stable branch; `main` is where work happens. Promote by merging into `production`, then deploy.

## Setup on a new machine

1. Install `pnpm`, `python3`, and `git`. Clone the repo.
2. Install the service:
   ```
   mkdir -p ~/.config/systemd/user
   cp deploy/driftguy-production.service ~/.config/systemd/user/
   systemctl --user edit driftguy-production.service   # optional: override BIND / PORT
   ```
3. Build the first release (creates the `production` worktree if missing):
   ```
   DRIFTGUY_PUBLIC_URL=http://<host>:5300 deploy/deploy.sh
   ```
4. Start it and keep it running across logouts and reboots:
   ```
   systemctl --user enable --now driftguy-production.service
   loginctl enable-linger "$USER"
   ```

`BIND` defaults to `0.0.0.0`; set it to a specific interface (for example a Tailscale address) with a drop-in override:

```
[Service]
Environment=BIND=100.x.y.z
```

## Deploying

Run `deploy/deploy.sh` after updating `production`. It refuses a dirty worktree, builds into `$DRIFTGUY_HOST_DIR/releases/<sha>`, flips the `current` symlink atomically, and keeps 5 releases. No service restart is needed.

Environment overrides: `DRIFTGUY_WORKTREE`, `DRIFTGUY_HOST_DIR` (default `~/.t3/hosted/driftguy`), `DRIFTGUY_PUBLIC_URL`.

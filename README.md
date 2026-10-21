# Server hardening Ansible playbook

Targets Ubuntu host. It updates and upgrades using APT before installing utilities, deploys the provided SSH and Fail2ban configs, installs Docker with the ArvanCloud registry mirror, creates `develop` user (inside docker group), adds optional public keys without deleting existing keys, schedules the resource check, and restricts inbound host and Docker-published traffic to TCP ports `6655`, `80`, and `443`.

## Configure before running

1. Copy `inventory.ini.example` to `inventory.ini` and set the real host, SSH user, and the **currently reachable SSH port**.
2. Edit `group_vars/servers.yml` and add your public keys before the first run. Example:

   ```yaml
   admin_authorized_keys:
     - "ssh-ed25519 AAAA... your-workstation"
   develop_authorized_keys:
     - "ssh-ed25519 AAAA... your-workstation"
   ```

   `admin_authorized_keys` are added to the account configured by `admin_ssh_user` (defaults to the inventory's `ansible_user`). `develop_authorized_keys` are added to `/home/develop/.ssh/authorized_keys`. Keys are appended; existing entries are not removed. Before changing SSH settings, the playbook checks that the administrator has an existing non-empty `authorized_keys` file or that at least one admin key was supplied.
3. The `templates/docker-port-allowlist.sh.j2` file is intentional: Ansible renders it into `/usr/local/sbin/docker-port-allowlist.sh`. It adds a `DOCKER-USER` filter because UFW alone does not reliably restrict Docker-published forwarded ports. The interface defaults to the host's detected IPv4 default-route interface; override `docker_external_interface` if needed.
4. Install the required Ansible collection and run:

   ```bash
   ansible-galaxy collection install -r requirements.yml
   ansible-playbook -i inventory.ini site.yml
   ```

After deployment, SSH listens on port `6655`. Keep the current SSH session open until a new key-based connection on port `6655` has been verified; then update `ansible_port=6655` in inventory for later runs.

## What it configures

- Runs APT index update and package upgrade before installing `htop`, `tmux`, `fish`, `fail2ban`, and required packages.
- Downloads `/root/install-docker.sh` from `https://get.docker.com` and runs it only if `/usr/bin/docker` is not present.
- Sets `/etc/docker/daemon.json` to use `https://docker.arvancloud.ir` as a registry mirror. Docker's `insecure-registries` option is configured with the hostname `docker.arvancloud.ir` (without the URL scheme, as expected by Docker).
- Logs out root from the default Docker registry if credentials exist, reloads systemd when required, and restarts Docker if installation or daemon configuration changes.
- Creates user `develop` with fish as the shell and membership in the `docker` group. Its password hash corresponds to the password provided for this task; only the hash is stored in the playbook. Membership in the `docker` group grants root-equivalent privileges.
- Installs optional public keys for both the current Ansible SSH user and `develop` without removing other authorized keys.
- Adds a Docker `DOCKER-USER` filter so Docker-published inbound ports are restricted to TCP `6655`, `80`, and `443` on the detected external interface, in addition to the UFW rules. Set `docker_external_interface` in `group_vars/servers.yml` if the public interface differs from the default IPv4 interface. The UFW rule reconciliation uses whitespace-tolerant matching so normal column alignment in `ufw status` does not trigger a reset on every run.
- Sets `/etc/ssh/sshd_config.d/50-cloud-init.conf` to `PasswordAuthentication no` and validates the final SSH configuration.
- Installs `/etc/fail2ban/jail.local`, sets the SSH jail port to `6655`, and enables Fail2ban.
- Installs `/root/check_resources.sh` with mode `0744` and runs it every two minutes from root's crontab.
- Keeps UFW inbound and routed traffic default-deny and allows only TCP `6655`, `80`, and `443` for both IPv4 and IPv6.

## Notes

- The playbook intentionally fails before SSH configuration changes if it cannot verify a key-based fallback for the Ansible SSH user. If the user's key is stored outside `~/.ssh/authorized_keys`, add its public key to `admin_authorized_keys`.
- If the first run currently connects on port `22`, leave `ansible_port=22` until the playbook finishes; switch it to `6655` only after confirming connectivity.
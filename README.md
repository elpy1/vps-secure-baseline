# VPS secure baseline

An Ansible baseline for new VPS hosts with sane hardening defaults for:

- RHEL-family 9+ systems such as Rocky Linux and AlmaLinux
- Debian 12+
- Ubuntu 22.04+

The playbook applies a small, distro-aware baseline:

- baseline admin packages
- upgrade installed distro packages on first run
- persistent journald storage and split sysctl tuning/security drop-ins
- SSH hardening with a managed `sshd_config.d` drop-in
- `firewalld` on RHEL-family hosts and `ufw` on Debian-family hosts
- `fail2ban`
- automatic security updates with `dnf-automatic` or `unattended-upgrades`
- zram via the distro-native generator package

## Scope

> [!WARNING]
> This repo is intended as a secure bootstrap baseline for new VPS servers.

It is not designed to be applied blindly to already-running or long-lived
servers. By default it can perform a full package upgrade, enforce SSH policy,
enable automatic security updates, and activate host firewall management. Those
are reasonable first-run bootstrap defaults, but they can be disruptive on an
established host if you have not reviewed and adapted the variables first.

## Layout

- `site.yml`: main playbook
- `inventory/hosts.yml`: tracked example inventory
- `inventory/hosts.local.yml`: optional local inventory override, ignored by git
- `group_vars/all.yml`: baseline tunables
- `roles/`: distro-aware roles

`playbook.yml` is kept as a compatibility wrapper that imports `site.yml`.

## Usage

1. Install the required collections:

   ```bash
   ansible-galaxy collection install -r requirements.yml
   ```

2. Add your servers to `inventory/hosts.local.yml` or edit `inventory/hosts.yml`.

   For a fresh VPS where you are connecting as `root`:

   ```yaml
   all:
     children:
       vps:
         hosts:
           my-vps:
             ansible_host: 203.0.113.10
             ansible_user: root
             ansible_become: false
   ```

   For a host where you connect with a sudo-capable user:

   ```yaml
   all:
     children:
       vps:
         hosts:
           my-vps:
             ansible_host: 203.0.113.10
             ansible_user: deploy
   ```

3. Adjust any defaults in `group_vars/all.yml`.

   By default the firewall only opens the configured SSH port. Add any
   application ports you need to `firewall_allowed_tcp_ports` or
   `firewall_allowed_udp_ports`.

   The baseline keeps `zram` enabled with a moderate `base_swappiness`
   for small web/app VPS instances. For DB-heavy hosts, consider
   disabling `zram` or lowering `base_swappiness`.

4. Run the baseline:

   ```bash
   ansible-playbook site.yml
   ```

   Or use the helper script:

   ```bash
   ./deploy.sh
   ```

   For an initial rollout, prefer limiting the run to one host at a time:

   ```bash
   ansible-playbook site.yml -l my-vps
   ```

## Notes

- The playbook runs with `become: true` by default, but it can also be used during bootstrap as `root` with `ansible_become: false`.
- Installed distro packages are upgraded by default before the baseline applies service config. Disable `base_upgrade_installed_packages` if you need to manage package upgrades separately.
- Debian-family automatic updates are explicitly limited to security origins. On Ubuntu, this can leave some security-related updates pending if they require new dependencies from the non-security release pocket.
- On older RHEL-family images, the initial package sync may erase obsolete legacy packages such as `network-scripts` so the host can move to the current package set cleanly.
- On RHEL-family hosts, the baseline ensures `NetworkManager` is installed and enabled before that initial package sync.
- SSH password auth is disabled by default, so ensure key-based access is working before applying it.
- The SSH role refuses to disable password auth unless one of the checked users has a non-empty `authorized_keys` file. By default it checks `ansible_user`; override `sshd_authorized_keys_check_users` or set `sshd_skip_authorized_keys_check: true` if you rely on external SSH auth such as `AuthorizedKeysCommand` or SSH certificates.
- On RHEL-family hosts, EPEL is enabled by default because `fail2ban` is commonly sourced from it.

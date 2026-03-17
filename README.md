# VPS secure baseline

An Ansible baseline for new VPS hosts with sane hardening defaults for:

- Rocky Linux 9+
- AlmaLinux 9+
- Debian 12+
- Ubuntu 22.04+

The playbook applies a small, distro-aware baseline:

- baseline admin packages
- upgrade installed distro packages after the initial firewall/SSH safety steps
- distro-native NTP/time synchronization with an explicit synchronization check
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

   `site.yml` targets the `vps` group, so put baseline-managed hosts there.

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

   On RHEL-family hosts, the `firewalld` backend also supports
   `firewall_allowed_services` for named firewalld services.
   On Debian-family hosts, `firewall_allowed_services` is not supported.

   On Debian-family hosts, the UFW backend rebuilds the managed ruleset
   when the desired policies, allowed port lists, or managed IPv6 setting
   change so removed ports are converged too. By default it also manages
   `/etc/default/ufw` `IPV6=` explicitly based on detected default IPv6
   connectivity; override `firewall_ufw_ipv6` if needed.

   The baseline keeps `zram` enabled with a moderate `base_swappiness`
   for small web/app VPS instances. For DB-heavy hosts, consider
   disabling `zram` or lowering `base_swappiness`.

   Time synchronization is enforced as part of the baseline. Increase
   `time_sync_wait_retries` or `time_sync_wait_delay` if your provider's
   NTP service typically takes longer to report synchronized.

4. Run the baseline:

   ```bash
   ansible-playbook site.yml
   ```

   Or use the helper script:

   ```bash
   ./deploy.sh
   ```

   The play already runs one host at a time (`serial: 1`) and stops on the
   first host error (`any_errors_fatal: true`). Use `-l` if you want to start
   with a single named host anyway:

   ```bash
   ansible-playbook site.yml -l my-vps
   ```

## Notes

- The playbook runs with `become: true` by default, but it can also be used during bootstrap as `root` with `ansible_become: false`.
- Installed distro packages are upgraded on every playbook run while `base_upgrade_installed_packages: true`, after the initial firewall/SSH safety steps and time synchronization checks but before the remaining baseline config is applied. Disable it if you need to manage package upgrades separately.
- Debian-family automatic updates are explicitly limited to security origins. On Ubuntu, this can leave some security-related updates pending if they require new dependencies from the non-security release pocket.
- On older RHEL-family images, the initial package sync may erase obsolete legacy packages such as `network-scripts` so the host can move to the current package set cleanly.
- On RHEL-family hosts, the baseline ensures `NetworkManager` is installed and enabled before that initial package sync.
- On RHEL-family hosts, the firewall role reconciles the selected firewalld zone more explicitly: it requires an explicit interface binding target, manages the zone target, removes stale ports/services from that zone, reloads firewalld to collapse runtime-only drift, and currently requires `firewall_default_outgoing_policy: allow`.
- Time synchronization is managed explicitly and must report synchronized before the play continues. The baseline uses `chrony` on RHEL-family hosts and `systemd-timesyncd` on Debian-family hosts.
- When changing `sshd_port`, the play asserts the final firewall policy permits that port, temporarily keeps the current Ansible SSH port open, reconnects Ansible on the new port, and only then removes the transitional port allowance.
- On Debian-family systemd hosts, the SSH role disables `ssh.socket` and manages `ssh.service` directly so `sshd_port` changes are authoritative even on images that default to socket activation.
- On SELinux-enabled RHEL-family hosts, non-default SSH ports are added to the SELinux `ssh_port_t` policy, and only the last custom SSH SELinux port previously managed by this repo is removed again when `sshd_port` changes.
- `zram_enabled` and `automatic_updates_enabled` currently control whether those roles run on future plays. Setting them to `false` does not remove zram or automatic update configuration that a previous run already applied.
- SSH password auth is disabled by default, so ensure key-based access is working before applying it.
- The SSH role refuses to disable password auth unless one of the checked users has a non-empty `authorized_keys` file. By default it checks `ansible_user`; override `sshd_authorized_keys_check_users` or set `sshd_skip_authorized_keys_check: true` if you rely on external SSH auth such as `AuthorizedKeysCommand` or SSH certificates.
- On RHEL-family hosts, EPEL is enabled by default because `fail2ban` is commonly sourced from it.

## SSH Port Changes

If the current controller-to-host SSH port is not already represented by
`ansible_port`, set `sshd_current_connection_port_override` explicitly for the
first port-change run.

When host key verification is enabled, expect the first connection to the new
port to be treated as a separate `known_hosts` entry. Review the new-port host
key rather than blindly trusting it:

```bash
ssh-keygen -F "[203.0.113.10]:2222"
ssh-keygen -R "[203.0.113.10]:2222"
ssh-keyscan -p 2222 203.0.113.10
```

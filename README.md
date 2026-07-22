# GCU Scripts

IT automation scripts and configuration files for Glasgow Caledonian University — covering macOS endpoint management via Jamf Pro, Windows lab VM provisioning, printer deployment, and file migration.

---

## Repository Structure

```
GCU-Scirpts/
├── jamf/               # macOS management scripts (Jamf Pro)
├── hyperv/             # Windows 11 Hyper-V lab VM automation
├── appsanywhere/       # AppsAnywhere VM build files
├── printers/           # Printer deployment scripts
├── Printers/ThirdFloor/# Third-floor printer configuration
├── raillive/           # Rail Live integration scriptsa
├── robocopy/           # File migration / Robocopy jobs
└── sccm-mdt/           # SCCM / MDT deployment scripts
```

**Languages:** Shell · PowerShell · Batch

---

## macOS — Jamf Pro Scripts (`jamf/`)

All scripts are designed to run as Jamf Pro policies. Most accept script parameters — check the header of each file for parameter details.

### Application Deployment

| Script | Description |
|--------|-------------|
| `cisco-secure-client-deploy.sh` | Installs Cisco Secure Client 5.1.10.233 (VPN-only) with DNS restoration for Jamf Security Cloud compatibility |
| `microsoft-teams-deploy.sh` | Deploys Microsoft Teams |
| `sophos-endpoint-deploy.sh` | Installs Sophos Endpoint Protection |

### System Management

| Script | Description |
|--------|-------------|
| `jamf-protect-deploy.sh` | Installs the Jamf Protect security agent |
| `enable-filevault.sh` | Enables FileVault encryption |

### Utilities

| Script | Description |
|--------|-------------|
| `cleanup-old-profiles.sh` | Removes outdated configuration profiles |
| `inventory-update.sh` | Forces a Jamf inventory submission |

### Usage

Scripts run via Jamf Pro policies. To test locally:

```bash
sudo bash script-name.sh
```

> Scripts include error handling, logging, and cleanup. Test in a pilot scope before pushing to production.

---

## Windows — Hyper-V Lab VM (`hyperv/`)

Automates the creation of a Windows 11 Pro Hyper-V VM with a local account and fully unattended setup — no Microsoft account prompt, no manual setup screens.

**VM spec**

| Setting | Value |
|---------|-------|
| Computer name | `appsanywhere` |
| Local admin | `apps` / `apps` |
| Edition | Windows 11 Pro |
| Disk | 200 GB dynamic VHDX |
| RAM | 4 GB |
| CPUs | 2 |

**Files**

| File | Purpose |
|------|---------|
| `autounattend.xml` | Windows answer file — selects Pro edition, sets computer name, creates local account |
| `build-iso.ps1` | Mounts the official Windows ISO, injects the answer file, rebuilds a bootable ISO |
| `createhyper-v.ps1` | Creates the Hyper-V VM and starts it |

**Prerequisites**

- Windows 11 host with Hyper-V enabled
- [Windows ADK](https://aka.ms/adk) — Deployment Tools component only
- Windows 11 ISO from [microsoft.com](https://www.microsoft.com/software-download/windows11)

**Usage**

1. Copy your Windows 11 ISO to `C:\HyperV\` then build the unattended ISO:

```powershell
powershell -ExecutionPolicy RemoteSigned -File build-iso.ps1
```

2. Create and start the VM:

```powershell
powershell -ExecutionPolicy RemoteSigned -File createhyper-v.ps1
```

3. Open Hyper-V Manager and connect to `AppsAnywhere` — Windows installs fully unattended.

**Notes**

- The KMS client key in `autounattend.xml` selects Windows 11 Pro and suppresses the product key prompt. It does **not** activate Windows.
- The password is stored in plaintext in `autounattend.xml` — acceptable for isolated lab use.
- To reuse for a different machine name or account, edit `autounattend.xml` and re-run both scripts.

---

## AppsAnywhere (`appsanywhere/`)

Build and configuration files supporting the AppsAnywhere virtualised application delivery environment.

---

## Printers (`printers/`, `Printers/ThirdFloor/`)

Scripts and configuration for deploying network printers across campus, including third-floor print room setup.

---

## File Migration — Robocopy (`robocopy/`)

Batch scripts wrapping Robocopy jobs for bulk file migrations and server-to-server transfers.

---

## SCCM / MDT (`sccm-mdt/`)

Deployment scripts and task sequence support files for Microsoft Configuration Manager (SCCM) and the Microsoft Deployment Toolkit (MDT).

---

## Rail Live (`raillive/`)

Scripts supporting the Rail Live lab booking and resource management system.

---

## Licence

[GPL-3.0](LICENSE)

---

*Maintained by IT Services, Glasgow Caledonian University*

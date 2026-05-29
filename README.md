# GCU Scripts
Jamf Pro deployment and management scripts for Glasgow Caledonian University,
plus Windows lab VM automation tools.

## Contents

### Application Deployment
* `cisco-secure-client-deploy.sh` - Cisco Secure Client 5.1.10.233 VPN-only installation with DNS restoration for Jamf Security Cloud compatibility
* `microsoft-teams-deploy.sh` - Microsoft Teams deployment script
* `sophos-endpoint-deploy.sh` - Sophos Endpoint Protection deployment

### System Management
* `jamf-protect-deploy.sh` - Jamf Protect security agent installation
* `enable-filevault.sh` - FileVault encryption enablement script

### Utilities
* `cleanup-old-profiles.sh` - Remove outdated configuration profiles
* `inventory-update.sh` - Force Jamf inventory submission

### Windows Lab VM
Automates the creation of a Windows 11 Pro Hyper-V VM with a local account,
no Microsoft account prompt, and no manual setup screens.

**Result**
- Computer name: `appsanywhere`
- Local admin account: `apps` / `apps`
- Edition: Windows 11 Pro
- Disk: 200GB dynamic VHDX
- RAM: 4GB
- CPUs: 2

**Prerequisites**
- Windows 11 host with Hyper-V enabled
- [Windows ADK](https://aka.ms/adk) — Deployment Tools component only
- Windows 11 ISO from [microsoft.com](https://www.microsoft.com/software-download/windows11)

**Files**
| File | Purpose |
|------|---------|
| `autounattend.xml` | Windows answer file — selects Pro, sets computer name, creates local account |
| `build-iso.ps1` | Mounts official Windows ISO, injects XML, rebuilds bootable ISO |
| `createhyper-v.ps1` | Creates and starts the Hyper-V VM |

**Usage**

1. Copy your Windows 11 ISO to `G:\` then build the unattended ISO:
```powershell
powershell -ExecutionPolicy RemoteSigned -File build-iso.ps1
```

2. Create and start the VM:
```powershell
powershell -ExecutionPolicy RemoteSigned -File createhyper-v.ps1
```

3. Open Hyper-V Manager and connect to the AppsAnywhere VM — Windows installs fully unattended.

**Notes**
- The KMS client key in `autounattend.xml` selects Windows 11 Pro and suppresses the product key prompt. It does not activate Windows.
- Password is stored in plaintext in `autounattend.xml` — fine for lab use.
- To reuse for a different machine name or account, edit `autounattend.xml` and re-run both scripts.

---

## Usage (macOS Scripts)
All scripts are designed to run via Jamf Pro policies. Most scripts accept 
parameters for customisation — check individual script headers for parameter details.

## Notes
Scripts follow macOS best practices and include error handling, logging, and 
cleanup routines. Test in a pilot environment before production deployment.

---

Maintained by: IT Services, Glasgow Caledonian University  
Last Updated: May 2026

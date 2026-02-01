# GCU Scripts

Jamf Pro deployment and management scripts for Glasgow Caledonian University.

## Contents

**Application Deployment**
- `cisco-secure-client-deploy.sh` - Cisco Secure Client 5.1.10.233 VPN-only installation with DNS restoration for Jamf Security Cloud compatibility
- `microsoft-teams-deploy.sh` - Microsoft Teams deployment script
- `sophos-endpoint-deploy.sh` - Sophos Endpoint Protection deployment

**System Management**
- `jamf-protect-deploy.sh` - Jamf Protect security agent installation
- `enable-filevault.sh` - FileVault encryption enablement script

**Utilities**
- `cleanup-old-profiles.sh` - Remove outdated configuration profiles
- `inventory-update.sh` - Force Jamf inventory submission

## Usage

All scripts are designed to run via Jamf Pro policies. Most scripts accept parameters for customization - check individual script headers for parameter details.

## Notes

Scripts follow macOS best practices and include error handling, logging, and cleanup routines. Test in a pilot environment before production deployment.

---

**Maintained by:** IT Services, Glasgow Caledonian University  
**Last Updated:** February 2026
